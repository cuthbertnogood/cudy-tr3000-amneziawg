#!/bin/sh
# AmneziaWG на Cudy: статус / чтение / apply из .conf или key=value.
#
#   awg-config.sh status
#   awg-config.sh get
#   awg-config.sh parse /tmp/awg.conf
#   awg-config.sh apply-file /tmp/awg.conf
#   awg-config.sh apply   # из env / stdin key=value (см. ниже)
#
set -eu

WG_IF="${WG_IF:-wg0}"
PEER="${PEER:-}"
KEYDIR="/etc/wireguard"
ENDPOINT_FILE="/etc/amnezia/endpoint"
HOTPLUG="/etc/hotplug.d/iface/99-awg-endpoint"

find_peer() {
	for s in ${PEER} wgvps wgserver; do
		[ -n "$s" ] || continue
		t=$(uci -q get "network.${s}" 2>/dev/null || true)
		case "$t" in
			amneziawg_${WG_IF}|wireguard_${WG_IF}) echo "$s"; return 0 ;;
		esac
	done
	# любой peer к этому if
	i=0
	while uci -q get "network.@amneziawg_${WG_IF}[$i]" >/dev/null 2>&1; do
		# имя секции через show — у OpenWrt анонимные редки; ищем по типу
		i=$((i + 1))
	done
	echo 'wgserver'
}

peer_name() {
	p=$(find_peer)
	echo "${p:-wgserver}"
}

trim() {
	printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Парсит .conf → KEY=VAL на stdout (без PrivateKey в лог-строках ошибок)
parse_conf_file() {
	conf="$1"
	[ -f "$conf" ] || { echo "error=no_file" >&2; return 1; }

	priv=''; addr=''; dns=''; mtu='1280'
	jc='4'; jmin='40'; jmax='70'; s1='0'; s2='0'
	h1='1'; h2='2'; h3='3'; h4='4'
	spub=''; endpoint=''; eport='443'; allowed='0.0.0.0/0'; ka='25'
	section=''

	while IFS= read -r line || [ -n "$line" ]; do
		line=$(printf '%s' "$line" | tr -d '\r')
		case "$line" in
			''|\#*) continue ;;
			\[Interface\]|\[interface\]) section=if; continue ;;
			\[Peer\]|\[peer\]) section=peer; continue ;;
		esac
		key=$(printf '%s' "$line" | sed 's/[[:space:]]*=.*//')
		val=$(printf '%s' "$line" | sed 's/^[^=]*=[[:space:]]*//')
		key=$(trim "$key")
		val=$(trim "$val")
		case "$section/$key" in
			if/PrivateKey|if/privatekey) priv=$val ;;
			if/Address|if/address) addr=$val ;;
			if/DNS|if/dns) dns=$val ;;
			if/MTU|if/mtu) mtu=$val ;;
			if/Jc|if/jc) jc=$val ;;
			if/Jmin|if/jmin) jmin=$val ;;
			if/Jmax|if/jmax) jmax=$val ;;
			if/S1|if/s1) s1=$val ;;
			if/S2|if/s2) s2=$val ;;
			if/H1|if/h1) h1=$val ;;
			if/H2|if/h2) h2=$val ;;
			if/H3|if/h3) h3=$val ;;
			if/H4|if/h4) h4=$val ;;
			peer/PublicKey|peer/publickey) spub=$val ;;
			peer/Endpoint|peer/endpoint)
				endpoint=${val%%:*}
				eport=${val##*:}
				[ "$endpoint" = "$val" ] && eport=443
				;;
			peer/AllowedIPs|peer/allowedips) allowed=$val ;;
			peer/PersistentKeepalive|peer/persistentkeepalive) ka=$val ;;
			# параметры маскировки иногда в [Peer]
			peer/Jc|peer/jc) jc=$val ;;
			peer/Jmin|peer/jmin) jmin=$val ;;
			peer/Jmax|peer/jmax) jmax=$val ;;
			peer/S1|peer/s1) s1=$val ;;
			peer/S2|peer/s2) s2=$val ;;
			peer/H1|peer/h1) h1=$val ;;
			peer/H2|peer/h2) h2=$val ;;
			peer/H3|peer/h3) h3=$val ;;
			peer/H4|peer/h4) h4=$val ;;
		esac
	done < "$conf"

	printf 'private_key=%s\n' "$priv"
	printf 'address=%s\n' "$addr"
	printf 'dns=%s\n' "$dns"
	printf 'mtu=%s\n' "$mtu"
	printf 'endpoint_host=%s\n' "$endpoint"
	printf 'endpoint_port=%s\n' "$eport"
	printf 'server_public_key=%s\n' "$spub"
	printf 'allowed_ips=%s\n' "$allowed"
	printf 'keepalive=%s\n' "$ka"
	printf 'awg_jc=%s\n' "$jc"
	printf 'awg_jmin=%s\n' "$jmin"
	printf 'awg_jmax=%s\n' "$jmax"
	printf 'awg_s1=%s\n' "$s1"
	printf 'awg_s2=%s\n' "$s2"
	printf 'awg_h1=%s\n' "$h1"
	printf 'awg_h2=%s\n' "$h2"
	printf 'awg_h3=%s\n' "$h3"
	printf 'awg_h4=%s\n' "$h4"
}

load_kv_into_env() {
	# читает KEY=VAL; пустые private_key не затирают текущий
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
			''|\#*) continue ;;
		esac
		k=${line%%=*}
		v=${line#*=}
		case "$k" in
			private_key) [ -n "$v" ] && PRIVATE_KEY=$v ;;
			address) ADDRESS=$v ;;
			dns) DNS=$v ;;
			mtu) MTU=$v ;;
			endpoint_host) ENDPOINT_HOST=$v ;;
			endpoint_port) ENDPOINT_PORT=$v ;;
			server_public_key) SERVER_PUBLIC_KEY=$v ;;
			allowed_ips) ALLOWED_IPS=$v ;;
			keepalive) KEEPALIVE=$v ;;
			awg_jc) AWG_JC=$v ;;
			awg_jmin) AWG_JMIN=$v ;;
			awg_jmax) AWG_JMAX=$v ;;
			awg_s1) AWG_S1=$v ;;
			awg_s2) AWG_S2=$v ;;
			awg_h1) AWG_H1=$v ;;
			awg_h2) AWG_H2=$v ;;
			awg_h3) AWG_H3=$v ;;
			awg_h4) AWG_H4=$v ;;
		esac
	done
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
		echo "$((a / 3600)) ч $(( (a % 3600) / 60 )) мин"
	fi
}

cmd_status() {
	p=$(peer_name)
	ep=$(uci -q get "network.${p}.endpoint_host" 2>/dev/null || true)
	eport=$(uci -q get "network.${p}.endpoint_port" 2>/dev/null || true)
	addr=$(uci -q get "network.${WG_IF}.addresses" 2>/dev/null || true)
	addr=$(printf '%s' "$addr" | head -n1)
	[ -n "$addr" ] || addr=$(uci -q get "network.${WG_IF}.ipaddr" 2>/dev/null || true)
	# runtime endpoint важнее UCI
	rt_ep=$(awg show "${WG_IF}" endpoints 2>/dev/null | awk 'NR==1 {print $2; exit}')
	if [ -n "$rt_ep" ] && [ "$rt_ep" != "(none)" ]; then
		ep=${rt_ep%%:*}
		eport=${rt_ep##*:}
	fi
	hs=$(awg show "${WG_IF}" latest-handshakes 2>/dev/null | awk 'NR==1 {print $2; exit}')
	hs=${hs:-0}
	now=$(date +%s)
	age=99999
	[ "$hs" != "0" ] && [ -n "$hs" ] && age=$((now - hs))
	tunnel=down
	[ "$age" -le 120 ] && tunnel=up
	printf 'tunnel=%s\n' "$tunnel"
	printf 'handshake_age=%s\n' "$age"
	printf 'handshake_age_human=%s\n' "$(fmt_age "$age")"
	printf 'endpoint_host=%s\n' "${ep:-}"
	printf 'endpoint_port=%s\n' "${eport:-}"
	printf 'address=%s\n' "${addr:-}"
	printf 'peer=%s\n' "$p"
}

# Детальная статистика для страницы «Статус VPN»
cmd_stats() {
	cmd_status

	iface_up=0
	ip link show "${WG_IF}" 2>/dev/null | grep -q 'UP' && iface_up=1 || true
	printf 'iface_up=%s\n' "$iface_up"

	mtu=$(uci -q get "network.${WG_IF}.mtu" 2>/dev/null || true)
	[ -n "$mtu" ] || mtu=$(ip -o link show "${WG_IF}" 2>/dev/null | sed -n 's/.*mtu \([0-9]*\).*/\1/p')
	printf 'mtu=%s\n' "${mtu:-}"

	listen=$(awg show "${WG_IF}" 2>/dev/null | awk '/listening port:/ {print $3; exit}')
	printf 'listen_port=%s\n' "${listen:-}"

	client_pub=$(awg show "${WG_IF}" 2>/dev/null | awk '/^  public key:/ {print $3; exit}')
	[ -n "$client_pub" ] || client_pub=$(cat "${KEYDIR}/${WG_IF}.pub" 2>/dev/null || true)
	printf 'client_public_key=%s\n' "${client_pub:-}"

	server_pub=$(awg show "${WG_IF}" peers 2>/dev/null | awk 'NR==1 {print; exit}')
	[ -n "$server_pub" ] || server_pub=$(uci -q get "network.$(peer_name).public_key" 2>/dev/null || true)
	printf 'server_public_key=%s\n' "${server_pub:-}"

	ka=$(awg show "${WG_IF}" 2>/dev/null | awk '/persistent keepalive:/ {print $3; exit}')
	[ -n "$ka" ] || ka=$(uci -q get "network.$(peer_name).persistent_keepalive" 2>/dev/null || true)
	printf 'keepalive=%s\n' "${ka:-}"

	rx=0; tx=0
	xfer=$(awg show "${WG_IF}" transfer 2>/dev/null | awk 'NR==1 {print $2, $3; exit}')
	rx=${xfer%% *}; tx=${xfer##* }
	rx=${rx:-0}; tx=${tx:-0}
	printf 'rx_bytes=%s\n' "$rx"
	printf 'tx_bytes=%s\n' "$tx"
	printf 'rx_human=%s\n' "$(fmt_bytes "$rx")"
	printf 'tx_human=%s\n' "$(fmt_bytes "$tx")"

	allowed=$(awg show "${WG_IF}" allowed-ips 2>/dev/null | awk 'NR==1 {$1=""; sub(/^ /,""); print; exit}')
	printf 'allowed_ips=%s\n' "${allowed:-}"

	def=$(ip -4 route show default 2>/dev/null | head -n1)
	printf 'default_route=%s\n' "${def:-}"

	# uplink WISP
	up5=0; up24=0
	ifstatus wwan5 2>/dev/null | grep -q '"up": true' && up5=1 || true
	ifstatus wwan24 2>/dev/null | grep -q '"up": true' && up24=1 || true
	ssid5=$(uci -q get wireless.sta_wisp5.ssid 2>/dev/null || true)
	ssid24=$(uci -q get wireless.sta_wisp24.ssid 2>/dev/null || true)
	printf 'wwan5_up=%s\n' "$up5"
	printf 'wwan24_up=%s\n' "$up24"
	printf 'ssid5=%s\n' "${ssid5:-}"
	printf 'ssid24=%s\n' "${ssid24:-}"

	ep_via=$(ip -4 route get "$(uci -q get network.$(peer_name).endpoint_host 2>/dev/null || cat "$ENDPOINT_FILE" 2>/dev/null || echo 8.8.8.8)" 2>/dev/null | head -n1)
	printf 'endpoint_route=%s\n' "${ep_via:-}"

	# сырой dump (многострочный → одна строка с | )
	dump=$(awg show "${WG_IF}" 2>/dev/null | tr '\n' '|' | sed 's/|$//')
	printf 'awg_dump=%s\n' "${dump:-}"

	now=$(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date)
	printf 'updated_at=%s\n' "$now"
}

cmd_get() {
	p=$(peer_name)
	# private_key не отдаём в UI — пусто = «не менять»
	printf 'private_key=\n'
	addr=$(uci -q get "network.${WG_IF}.addresses" 2>/dev/null || true)
	# uci может вернуть несколько через \n
	addr=$(printf '%s' "$addr" | head -n1)
	printf 'address=%s\n' "${addr:-}"
	printf 'mtu=%s\n' "$(uci -q get "network.${WG_IF}.mtu" 2>/dev/null || echo 1280)"
	printf 'endpoint_host=%s\n' "$(uci -q get "network.${p}.endpoint_host" 2>/dev/null || true)"
	printf 'endpoint_port=%s\n' "$(uci -q get "network.${p}.endpoint_port" 2>/dev/null || echo 443)"
	printf 'server_public_key=%s\n' "$(uci -q get "network.${p}.public_key" 2>/dev/null || true)"
	allowed=$(uci -q get "network.${p}.allowed_ips" 2>/dev/null || echo '0.0.0.0/0')
	allowed=$(printf '%s' "$allowed" | head -n1)
	printf 'allowed_ips=%s\n' "${allowed:-0.0.0.0/0}"
	printf 'keepalive=%s\n' "$(uci -q get "network.${p}.persistent_keepalive" 2>/dev/null || echo 25)"
	printf 'awg_jc=%s\n' "$(uci -q get "network.${WG_IF}.awg_jc" 2>/dev/null || echo 4)"
	printf 'awg_jmin=%s\n' "$(uci -q get "network.${WG_IF}.awg_jmin" 2>/dev/null || echo 40)"
	printf 'awg_jmax=%s\n' "$(uci -q get "network.${WG_IF}.awg_jmax" 2>/dev/null || echo 70)"
	printf 'awg_s1=%s\n' "$(uci -q get "network.${WG_IF}.awg_s1" 2>/dev/null || echo 0)"
	printf 'awg_s2=%s\n' "$(uci -q get "network.${WG_IF}.awg_s2" 2>/dev/null || echo 0)"
	printf 'awg_h1=%s\n' "$(uci -q get "network.${WG_IF}.awg_h1" 2>/dev/null || echo 1)"
	printf 'awg_h2=%s\n' "$(uci -q get "network.${WG_IF}.awg_h2" 2>/dev/null || echo 2)"
	printf 'awg_h3=%s\n' "$(uci -q get "network.${WG_IF}.awg_h3" 2>/dev/null || echo 3)"
	printf 'awg_h4=%s\n' "$(uci -q get "network.${WG_IF}.awg_h4" 2>/dev/null || echo 4)"
	dns=$(uci -q get dhcp.@dnsmasq[0].server 2>/dev/null | head -n1 || true)
	printf 'dns=%s\n' "${dns:-1.1.1.1}"
	printf 'client_public_key=%s\n' "$(cat "${KEYDIR}/${WG_IF}.pub" 2>/dev/null || true)"
}

apply_values() {
	ADDRESS=${ADDRESS:-}
	ENDPOINT_HOST=${ENDPOINT_HOST:-}
	ENDPOINT_PORT=${ENDPOINT_PORT:-443}
	SERVER_PUBLIC_KEY=${SERVER_PUBLIC_KEY:-}
	ALLOWED_IPS=${ALLOWED_IPS:-0.0.0.0/0}
	KEEPALIVE=${KEEPALIVE:-25}
	MTU=${MTU:-1280}
	DNS=${DNS:-1.1.1.1}
	AWG_JC=${AWG_JC:-4}
	AWG_JMIN=${AWG_JMIN:-40}
	AWG_JMAX=${AWG_JMAX:-70}
	AWG_S1=${AWG_S1:-0}
	AWG_S2=${AWG_S2:-0}
	AWG_H1=${AWG_H1:-1}
	AWG_H2=${AWG_H2:-2}
	AWG_H3=${AWG_H3:-3}
	AWG_H4=${AWG_H4:-4}

	[ -n "$ENDPOINT_HOST" ] || { echo "error=need_endpoint" >&2; return 1; }
	[ -n "$SERVER_PUBLIC_KEY" ] || { echo "error=need_server_pubkey" >&2; return 1; }
	[ -n "$ADDRESS" ] || { echo "error=need_address" >&2; return 1; }

	mkdir -p "$KEYDIR" /etc/amnezia
	chmod 700 "$KEYDIR"

	if [ -n "${PRIVATE_KEY:-}" ]; then
		printf '%s\n' "$PRIVATE_KEY" > "${KEYDIR}/${WG_IF}.key"
		chmod 600 "${KEYDIR}/${WG_IF}.key"
	fi
	if [ ! -s "${KEYDIR}/${WG_IF}.key" ]; then
		echo "error=no_private_key" >&2
		return 1
	fi
	CLIENT_PRIV=$(cat "${KEYDIR}/${WG_IF}.key")
	if command -v awg >/dev/null 2>&1; then
		awg pubkey < "${KEYDIR}/${WG_IF}.key" > "${KEYDIR}/${WG_IF}.pub" 2>/dev/null || true
	fi

	old_ep=$(uci -q get network.wgvps.endpoint_host 2>/dev/null || true)
	[ -n "$old_ep" ] || old_ep=$(uci -q get network.wgserver.endpoint_host 2>/dev/null || true)
	[ -n "$old_ep" ] || old_ep=$(cat "$ENDPOINT_FILE" 2>/dev/null || true)

	p=$(peer_name)
	# каноническое имя
	if [ "$p" != "wgserver" ] && [ "$p" != "wgvps" ]; then
		p=wgserver
	fi
	# если был wgvps — оставляем имя, чтобы не плодить секции
	[ -n "$(uci -q get network.wgvps 2>/dev/null || true)" ] && p=wgvps
	[ -z "$(uci -q get "network.${p}" 2>/dev/null || true)" ] && p=wgserver

	ifdown "${WG_IF}" 2>/dev/null || true

	# снять старый host-route, если endpoint сменился
	if [ -n "$old_ep" ] && [ "$old_ep" != "$ENDPOINT_HOST" ]; then
		ip -4 route show "$old_ep" 2>/dev/null | while read -r line; do
			# shellcheck disable=SC2086
			ip route del $line 2>/dev/null || true
		done
	fi

	uci -q delete "network.${WG_IF}" || true
	uci set "network.${WG_IF}=interface"
	uci set "network.${WG_IF}.proto=amneziawg"
	uci set "network.${WG_IF}.private_key=${CLIENT_PRIV}"
	uci -q delete "network.${WG_IF}.addresses" || true
	uci add_list "network.${WG_IF}.addresses=${ADDRESS}"
	uci set "network.${WG_IF}.mtu=${MTU}"
	uci set "network.${WG_IF}.awg_jc=${AWG_JC}"
	uci set "network.${WG_IF}.awg_jmin=${AWG_JMIN}"
	uci set "network.${WG_IF}.awg_jmax=${AWG_JMAX}"
	uci set "network.${WG_IF}.awg_s1=${AWG_S1}"
	uci set "network.${WG_IF}.awg_s2=${AWG_S2}"
	uci set "network.${WG_IF}.awg_h1=${AWG_H1}"
	uci set "network.${WG_IF}.awg_h2=${AWG_H2}"
	uci set "network.${WG_IF}.awg_h3=${AWG_H3}"
	uci set "network.${WG_IF}.awg_h4=${AWG_H4}"

	# убрать второй peer-секцию, если переименовываем
	if [ "$p" = "wgserver" ]; then
		uci -q delete network.wgvps || true
	fi

	uci -q delete "network.${p}" || true
	uci set "network.${p}=amneziawg_${WG_IF}"
	uci set "network.${p}.description=amnezia"
	uci set "network.${p}.public_key=${SERVER_PUBLIC_KEY}"
	uci set "network.${p}.endpoint_host=${ENDPOINT_HOST}"
	uci set "network.${p}.endpoint_port=${ENDPOINT_PORT}"
	uci -q delete "network.${p}.allowed_ips" || true
	# AllowedIPs через запятую — без pipe (ash subshell)
	_ips=$(printf '%s' "$ALLOWED_IPS" | tr ',' ' ')
	for a in ${_ips}; do
		a=$(trim "$a")
		[ -n "$a" ] && uci add_list "network.${p}.allowed_ips=${a}"
	done
	uci set "network.${p}.route_allowed_ips=1"
	uci set "network.${p}.persistent_keepalive=${KEEPALIVE}"
	uci commit network

	printf '%s\n' "$ENDPOINT_HOST" > "$ENDPOINT_FILE"
	chmod 644 "$ENDPOINT_FILE"

	# В обычном режиме конфиг пира сохраняем, но туннель не поднимаем.
	tm=$(cat /etc/amnezia/traffic-mode 2>/dev/null || echo vpn)
	if [ "$tm" = wisp ] && [ -x /usr/libexec/awg-mode.sh ]; then
		/usr/libexec/awg-mode.sh set-wisp >/dev/null
	else
		dns1=$(printf '%s' "$DNS" | tr ',' ' ' | awk '{print $1}')
		[ -n "$dns1" ] || dns1=1.1.1.1
		uci set dhcp.@dnsmasq[0].noresolv='1'
		uci -q delete dhcp.@dnsmasq[0].server || true
		uci add_list dhcp.@dnsmasq[0].server="${dns1}"
		uci commit dhcp

		/etc/init.d/network reload >/dev/null 2>&1 || true
		sleep 4
		/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true

		if [ -x "$HOTPLUG" ]; then
			WG_ENDPOINT="$ENDPOINT_HOST" INTERFACE=wwan5 ACTION=ifup sh "$HOTPLUG" 2>/dev/null || true
			WG_ENDPOINT="$ENDPOINT_HOST" INTERFACE=wwan24 ACTION=ifup sh "$HOTPLUG" 2>/dev/null || true
		fi
		ifup "${WG_IF}" 2>/dev/null || true
		sleep 2
	fi

	printf 'applied=1\n'
	printf 'endpoint_host=%s\n' "$ENDPOINT_HOST"
	printf 'endpoint_port=%s\n' "$ENDPOINT_PORT"
	printf 'address=%s\n' "$ADDRESS"
	cmd_status
}

cmd_apply_file() {
	tmp=$(mktemp) || return 1
	parse_conf_file "$1" > "$tmp" || { rm -f "$tmp"; return 1; }
	PRIVATE_KEY=''; ADDRESS=''; DNS=''; MTU=''; ENDPOINT_HOST=''; ENDPOINT_PORT=''
	SERVER_PUBLIC_KEY=''; ALLOWED_IPS=''; KEEPALIVE=''
	AWG_JC=''; AWG_JMIN=''; AWG_JMAX=''; AWG_S1=''; AWG_S2=''
	AWG_H1=''; AWG_H2=''; AWG_H3=''; AWG_H4=''
	load_kv_into_env < "$tmp"
	rm -f "$tmp"
	apply_values
}

cmd_apply_stdin() {
	PRIVATE_KEY=''; ADDRESS=''; DNS=''; MTU=''; ENDPOINT_HOST=''; ENDPOINT_PORT=''
	SERVER_PUBLIC_KEY=''; ALLOWED_IPS=''; KEEPALIVE=''
	AWG_JC=''; AWG_JMIN=''; AWG_JMAX=''; AWG_S1=''; AWG_S2=''
	AWG_H1=''; AWG_H2=''; AWG_H3=''; AWG_H4=''
	load_kv_into_env
	apply_values
}

case "${1:-}" in
	status) cmd_status ;;
	stats) cmd_stats ;;
	get) cmd_get ;;
	parse)
		[ -n "${2:-}" ] || { echo "usage: $0 parse FILE" >&2; exit 1; }
		parse_conf_file "$2"
		;;
	apply-file)
		[ -n "${2:-}" ] || { echo "usage: $0 apply-file FILE" >&2; exit 1; }
		cmd_apply_file "$2"
		;;
	apply)
		# env уже задан, или stdin key=value
		if [ -t 0 ]; then
			apply_values
		else
			cmd_apply_stdin
		fi
		;;
	*)
		echo "usage: $0 status|stats|get|parse FILE|apply-file FILE|apply" >&2
		exit 1
		;;
esac
