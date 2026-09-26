#!/bin/sh
# Режим трафика Cudy: обычный WISP или весь трафик в AmneziaWG.
#
#   awg-mode.sh status|connections|set-wisp|set-vpn|boot
#
# Файл режима: /etc/amnezia/traffic-mode  (wisp|vpn)
# UCI туннеля и ключи не удаляются: в wisp у wg0 auto=0 и ifdown.
set -eu

WG_IF="${WG_IF:-wg0}"
MODE_FILE="${MODE_FILE:-/etc/amnezia/traffic-mode}"
HOTPLUG="${HOTPLUG:-/etc/hotplug.d/iface/99-awg-endpoint}"
IF5="${IF5:-wwan5}"
IF24="${IF24:-wwan24}"

read_mode() {
	m=$(cat "${MODE_FILE}" 2>/dev/null || true)
	case "$m" in
		wisp|vpn) echo "$m" ;;
		*) echo vpn ;;
	esac
}

write_mode() {
	mkdir -p "$(dirname "${MODE_FILE}")"
	printf '%s\n' "$1" > "${MODE_FILE}"
}

fmt_bytes() {
	awk -v b="${1:-0}" 'BEGIN {
		if (b+0 < 1024) { printf "%d B", b+0; exit }
		if (b+0 < 1048576) { printf "%.2f KiB", b/1024; exit }
		if (b+0 < 1073741824) { printf "%.2f MiB", b/1048576; exit }
		printf "%.2f GiB", b/1073741824
	}'
}

fmt_age() {
	a=${1:-99999}
	case "$a" in
		''|*[!0-9]*) echo '—'; return ;;
	esac
	if [ "$a" -ge 99999 ]; then
		echo 'нет'
		return
	fi
	if [ "$a" -lt 60 ]; then
		echo "${a} с"
	elif [ "$a" -lt 3600 ]; then
		echo "$((a / 60)) мин $((a % 60)) с"
	else
		echo "$((a / 3600)) ч $(((a % 3600) / 60)) мин"
	fi
}

peer_sections() {
	uci show network 2>/dev/null | sed -n 's/^network\.\([A-Za-z0-9_]*\)=amneziawg_.*/\1/p'
}

set_peers_route() {
	val="$1"
	for s in $(peer_sections); do
		uci set "network.${s}.route_allowed_ips=${val}"
	done
}

peer_route_flag() {
	for s in $(peer_sections); do
		v=$(uci -q get "network.${s}.route_allowed_ips" 2>/dev/null || echo 0)
		if [ "$v" = 1 ]; then
			echo 1
			return 0
		fi
	done
	echo 0
}

has_fwd() {
	uci -q get "firewall.$1" >/dev/null 2>&1
}

# Удалить форвардинги lan → wan/wwan* (именованные и анонимные).
del_lan_wan_fw() {
	uci -q delete firewall.lan_wan || true
	i=0
	while uci -q get "firewall.@forwarding[$i]" >/dev/null 2>&1; do
		src=$(uci -q get "firewall.@forwarding[$i].src" || echo '')
		dst=$(uci -q get "firewall.@forwarding[$i].dest" || echo '')
		if [ "$src" = lan ]; then
			case "$dst" in
				wan|wwan|wwan5|wwan24)
					uci delete "firewall.@forwarding[$i]"
					continue
					;;
			esac
		fi
		i=$((i + 1))
	done
}

del_lan_wg_fw() {
	uci -q delete firewall.lan_wg || true
	i=0
	while uci -q get "firewall.@forwarding[$i]" >/dev/null 2>&1; do
		src=$(uci -q get "firewall.@forwarding[$i].src" || echo '')
		dst=$(uci -q get "firewall.@forwarding[$i].dest" || echo '')
		if [ "$src" = lan ] && [ "$dst" = wg ]; then
			uci delete "firewall.@forwarding[$i]"
			continue
		fi
		i=$((i + 1))
	done
}

ensure_fwd() {
	name="$1"
	dest="$2"
	uci -q delete "firewall.${name}" || true
	uci set "firewall.${name}=forwarding"
	uci set "firewall.${name}.src=lan"
	uci set "firewall.${name}.dest=${dest}"
}

set_wisp_uci() {
	uci set "network.${IF5}.defaultroute=1"
	uci set "network.${IF24}.defaultroute=1"
	uci set "network.${IF5}.peerdns=1"
	uci set "network.${IF24}.peerdns=1"
	uci set "network.${WG_IF}.auto=0"
	set_peers_route 0
	del_lan_wg_fw
	del_lan_wan_fw
	ensure_fwd lan_wan wan
	uci set dhcp.@dnsmasq[0].noresolv='0'
	uci -q delete dhcp.@dnsmasq[0].server || true
}

set_vpn_uci() {
	uci set "network.${IF5}.defaultroute=0"
	uci set "network.${IF24}.defaultroute=0"
	uci set "network.${IF5}.peerdns=0"
	uci set "network.${IF24}.peerdns=0"
	uci set "network.${WG_IF}.auto=1"
	set_peers_route 1
	del_lan_wan_fw
	del_lan_wg_fw
	ensure_fwd lan_wg wg
	uci set dhcp.@dnsmasq[0].noresolv='1'
	uci -q delete dhcp.@dnsmasq[0].server || true
	uci add_list dhcp.@dnsmasq[0].server='1.1.1.1'
	uci add_list dhcp.@dnsmasq[0].server='1.0.0.1'
}

commit_all() {
	uci commit network
	uci commit firewall
	uci commit dhcp
}

reload_services() {
	/etc/init.d/network reload >/dev/null 2>&1 || true
	/etc/init.d/firewall reload >/dev/null 2>&1 || true
	/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
}

drop_dev_default() {
	dev="$1"
	[ -n "$dev" ] || return 0
	ip route del default dev "$dev" 2>/dev/null || true
}

l3dev() {
	ifstatus "$1" 2>/dev/null | jsonfilter -e '@.l3_device' 2>/dev/null || true
}

bg_ifup_wisp() {
	(
		ifup "${IF5}" >/dev/null 2>&1 || true
		ifup "${IF24}" >/dev/null 2>&1 || true
	) >/dev/null 2>&1 &
}

in_sync() {
	mode="$1"
	auto=$(uci -q get "network.${WG_IF}.auto" 2>/dev/null || echo 1)
	dr=$(uci -q get "network.${IF5}.defaultroute" 2>/dev/null || echo 1)
	rr=$(peer_route_flag)
	nr=$(uci -q get dhcp.@dnsmasq[0].noresolv 2>/dev/null || echo 0)
	if [ "$mode" = wisp ]; then
		[ "$auto" = 0 ] || return 1
		[ "$dr" = 1 ] || return 1
		[ "$rr" = 0 ] || return 1
		[ "$nr" = 0 ] || return 1
		has_fwd lan_wan || return 1
		has_fwd lan_wg && return 1
		return 0
	fi
	[ "$auto" != 0 ] || return 1
	[ "$dr" = 0 ] || return 1
	[ "$rr" = 1 ] || return 1
	[ "$nr" = 1 ] || return 1
	has_fwd lan_wg || return 1
	has_fwd lan_wan && return 1
	return 0
}

apply_wisp() {
	write_mode wisp
	set_wisp_uci
	commit_all
	ifdown "${WG_IF}" >/dev/null 2>&1 || true
	drop_dev_default "${WG_IF}"
	reload_services
	bg_ifup_wisp
	logger -t awg-mode "traffic-mode=wisp"
	echo 'applied=wisp'
}

apply_vpn() {
	write_mode vpn
	set_vpn_uci
	commit_all
	reload_services
	if [ -x "$HOTPLUG" ]; then
		INTERFACE="${IF5}" ACTION=ifup "$HOTPLUG" >/dev/null 2>&1 || true
		INTERFACE="${IF24}" ACTION=ifup "$HOTPLUG" >/dev/null 2>&1 || true
	fi
	ifup "${WG_IF}" >/dev/null 2>&1 || true
	drop_dev_default "$(l3dev "${IF5}")"
	drop_dev_default "$(l3dev "${IF24}")"
	logger -t awg-mode "traffic-mode=vpn"
	echo 'applied=vpn'
}

tunnel_snapshot() {
	hs=$(awg show "${WG_IF}" latest-handshakes 2>/dev/null | awk 'NR==1 {print $2; exit}')
	hs=${hs:-0}
	now=$(date +%s)
	age=99999
	if [ "$hs" != 0 ] && [ -n "$hs" ]; then
		age=$((now - hs))
	fi
	tunnel=down
	[ "$age" -le 120 ] && tunnel=up
	wg_up=0
	ip link show "${WG_IF}" >/dev/null 2>&1 && wg_up=1
	xfer=$(awg show "${WG_IF}" transfer 2>/dev/null | awk 'NR==1 {print $2, $3; exit}')
	rx=$(echo "$xfer" | awk '{print $1}')
	tx=$(echo "$xfer" | awk '{print $2}')
	rx=${rx:-0}
	tx=${tx:-0}
	printf 'wg_up=%s\n' "$wg_up"
	printf 'tunnel=%s\n' "$tunnel"
	printf 'handshake_age=%s\n' "$age"
	printf 'handshake_age_human=%s\n' "$(fmt_age "$age")"
	printf 'rx_human=%s\n' "$(fmt_bytes "$rx")"
	printf 'tx_human=%s\n' "$(fmt_bytes "$tx")"
}

cmd_status() {
	up5=0
	up24=0
	ifstatus "${IF5}" 2>/dev/null | grep -q '"up": true' && up5=1 || true
	ifstatus "${IF24}" 2>/dev/null | grep -q '"up": true' && up24=1 || true
	printf 'mode=%s\n' "$(read_mode)"
	printf 'wwan5_up=%s\n' "$up5"
	printf 'wwan24_up=%s\n' "$up24"
	printf 'ssid5=%s\n' "$(uci -q get wireless.sta_wisp5.ssid 2>/dev/null || true)"
	printf 'ssid24=%s\n' "$(uci -q get wireless.sta_wisp24.ssid 2>/dev/null || true)"
	tunnel_snapshot
}

iface_addr() {
	ifstatus "$1" 2>/dev/null | jsonfilter -e '@["ipv4-address"][0].address' 2>/dev/null || true
}

iface_gw() {
	st=$(ifstatus "$1" 2>/dev/null || true)
	gw=$(printf '%s' "$st" | jsonfilter -e '@.route[0].nexthop' 2>/dev/null || true)
	[ -n "$gw" ] || gw=$(printf '%s' "$st" | jsonfilter -e '@["inactive"]["route"][0].nexthop' 2>/dev/null || true)
	printf '%s' "$gw"
}

cmd_connections() {
	cmd_status
	wifi_tsv=$(mktemp)
	assoc_tsv=$(mktemp)
	trap 'rm -f "$wifi_tsv" "$assoc_tsv"' EXIT

	iwinfo 2>/dev/null | awk '
		function flush() {
			if (iface != "")
				printf "%s\t%s\t%s\t%s\t%s\n", iface, mode, essid, channel, signal
		}
		BEGIN { iface = "" }
		$2 == "ESSID:" {
			flush()
			iface = $1
			essid = $0
			sub(/^[^"]*"/, "", essid)
			sub(/".*$/, "", essid)
			mode = ""
			channel = ""
			signal = ""
			next
		}
		$1 == "Mode:" {
			mode = $2
			for (i = 1; i <= NF; i++) if ($i == "Channel:") channel = $(i + 1)
			next
		}
		$1 == "Signal:" { signal = $2; next }
		END { flush() }
	' > "$wifi_tsv" || true

	ssid5=$(uci -q get wireless.sta_wisp5.ssid 2>/dev/null || true)
	ssid24=$(uci -q get wireless.sta_wisp24.ssid 2>/dev/null || true)
	sig5=''
	sig24=''
	while IFS=$(printf '\t') read -r iface mode essid channel signal; do
		[ -n "$iface" ] || continue
		case "$mode" in
			Client)
				if [ -n "$ssid5" ] && [ "$essid" = "$ssid5" ] && [ -z "$sig5" ]; then
					sig5=$signal
				fi
				if [ -n "$ssid24" ] && [ "$essid" = "$ssid24" ] && [ -z "$sig24" ]; then
					sig24=$signal
				fi
				;;
			Master)
				band=24
				case "$channel" in
					''|*[!0-9]*) band=24 ;;
					*) [ "$channel" -ge 36 ] && band=5 || true ;;
				esac
				iwinfo "$iface" assoclist 2>/dev/null | awk -v band="$band" -v essid="$essid" '
					$1 ~ /^[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:/ {
						sig = $2
						gsub(/[^0-9-]/, "", sig)
						mac = toupper($1)
						printf "%s\t%s\t%s\t%s\n", mac, sig, band, essid
					}
				' >> "$assoc_tsv" || true
				;;
		esac
	done < "$wifi_tsv"

	printf 'sig5=%s\n' "$sig5"
	printf 'sig24=%s\n' "$sig24"
	printf 'ip5=%s\n' "$(iface_addr "${IF5}")"
	printf 'gw5=%s\n' "$(iface_gw "${IF5}")"
	printf 'ip24=%s\n' "$(iface_addr "${IF24}")"
	printf 'gw24=%s\n' "$(iface_gw "${IF24}")"

	# mac \t ip \t name \t medium \t signal \t ssid
	leases=$(mktemp)
	if [ -f /tmp/dhcp.leases ]; then
		awk '{
			mac = toupper($2)
			name = $4
			if (name == "*" || name == "") name = "—"
			printf "%s\t%s\t%s\n", mac, $3, name
		}' /tmp/dhcp.leases > "$leases" || true
	else
		: > "$leases"
	fi

	neigh=$(mktemp)
	ip neigh show dev br-lan 2>/dev/null | awk '
		{
			ipaddr = $1
			mac = ""
			for (i = 1; i <= NF; i++) if ($i == "lladdr") mac = toupper($(i + 1))
			st = $NF
			if (mac == "" || st == "FAILED") next
			printf "%s\t%s\n", mac, ipaddr
		}
	' > "$neigh" || true

	awk -F '\t' '
		FILENAME == ARGV[1] {
			assoc[$1] = $2 "\t" $3 "\t" $4
			seen[$1] = 1
			next
		}
		FILENAME == ARGV[2] {
			lease_ip[$1] = $2
			lease_name[$1] = $3
			seen[$1] = 1
			next
		}
		FILENAME == ARGV[3] {
			neigh_ip[$1] = $2
			seen[$1] = 1
			next
		}
		END {
			for (mac in seen) {
				if (mac == "" || mac == "00:00:00:00:00:00") continue
				ipaddr = lease_ip[mac]
				if (ipaddr == "") ipaddr = neigh_ip[mac]
				if (ipaddr == "" || ipaddr == "192.168.10.1") continue
				name = lease_name[mac]
				if (name == "") name = "—"
				medium = "Ethernet"
				signal = ""
				ssid = ""
				if (mac in assoc) {
					split(assoc[mac], a, "\t")
					signal = a[1]
					if (a[2] == "5") medium = "5 ГГц"
					else medium = "2,4 ГГц"
					ssid = a[3]
				}
				printf "client\t%s\t%s\t%s\t%s\t%s\t%s\n", name, ipaddr, mac, medium, signal, ssid
			}
		}
	' "$assoc_tsv" "$leases" "$neigh" | sort -t "$(printf '\t')" -k2,2

	rm -f "$leases" "$neigh"
}

cmd_boot() {
	if [ ! -f "${MODE_FILE}" ]; then
		write_mode vpn
	fi
	mode=$(read_mode)
	if in_sync "$mode"; then
		echo "boot=ok mode=${mode}"
		return 0
	fi
	if [ "$mode" = wisp ]; then
		apply_wisp
	else
		apply_vpn
	fi
}

case "${1:-}" in
	status) cmd_status ;;
	connections) cmd_connections ;;
	set-wisp) apply_wisp; cmd_status ;;
	set-vpn) apply_vpn; cmd_status ;;
	boot) cmd_boot ;;
	*)
		echo "usage: $0 status|connections|set-wisp|set-vpn|boot" >&2
		exit 1
		;;
esac
