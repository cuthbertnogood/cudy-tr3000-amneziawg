#!/bin/sh
# Скан и смена WISP (чужой Wi‑Fi) на Cudy. Вызывается из LuCI-страницы.
#
#   wisp-switch.sh scan
#   WISP_SSID='Name' WISP_KEY='pass' WISP_BAND=auto|5|24 wisp-switch.sh apply
#   wisp-switch.sh status
#
set -eu

STA5="${STA5:-sta_wisp5}"
STA24="${STA24:-sta_wisp24}"
IF5="${IF5:-wwan5}"
IF24="${IF24:-wwan24}"
HOTPLUG="${HOTPLUG:-/etc/hotplug.d/iface/99-awg-endpoint}"

enc_from_scan() {
	e=$(echo "$1" | tr 'A-Z' 'a-z')
	case "$e" in
		*sae*|*wpa3*) echo 'sae' ;;
		*wpa2*|*psk2*|*ccmp*) echo 'psk2' ;;
		*wpa*|*psk*) echo 'psk' ;;
		*none*|*open*|'') echo 'none' ;;
		*) echo 'psk2' ;;
	esac
}

cmd_status() {
	ssid5=$(uci -q get "wireless.${STA5}.ssid" 2>/dev/null || true)
	ssid24=$(uci -q get "wireless.${STA24}.ssid" 2>/dev/null || true)
	up5=0; up24=0
	ifstatus "${IF5}" 2>/dev/null | grep -q '"up": true' && up5=1 || true
	ifstatus "${IF24}" 2>/dev/null | grep -q '"up": true' && up24=1 || true
	hs=$(awg show wg0 latest-handshakes 2>/dev/null | awk 'NR==1 {print $2; exit}')
	hs=${hs:-0}
	now=$(date +%s)
	age=99999
	[ "$hs" != "0" ] && [ -n "$hs" ] && age=$((now - hs))
	tunnel=down
	[ "$age" -le 120 ] && tunnel=up
	printf 'ssid5=%s\n' "$ssid5"
	printf 'ssid24=%s\n' "$ssid24"
	printf 'up5=%s\n' "$up5"
	printf 'up24=%s\n' "$up24"
	printf 'tunnel=%s\n' "$tunnel"
	printf 'handshake_age=%s\n' "$age"
}

cmd_scan() {
	tmp=$(mktemp)
	for radio in radio1 radio0; do
		default_band=24
		[ "$radio" = radio1 ] && default_band=5
		iwinfo "$radio" scan 2>/dev/null | awk -v defband="$default_band" '
			/^Cell / {
				if (ssid != "") {
					band = defband
					if (channel+0 >= 36) band = 5
					else if (channel+0 > 0) band = 24
					printf "%s|%s|%s|%s|%s\n", band, channel, signal, enc, ssid
				}
				ssid = ""; channel = 0; signal = 0; enc = "WPA2-PSK"
				next
			}
			/ESSID:/ {
				line=$0
				sub(/^[^"]*"/, "", line)
				sub(/".*$/, "", line)
				ssid = line
				next
			}
			/Channel:/ {
				for (i=1;i<=NF;i++) if ($i=="Channel:") channel=$(i+1)
				next
			}
			/Signal:/ {
				for (i=1;i<=NF;i++) if ($i=="Signal:") signal=$(i+1)
				next
			}
			/Encryption:/ {
				sub(/^.*Encryption:[[:space:]]*/, "")
				enc = $0
				next
			}
			END {
				if (ssid != "") {
					band = defband
					if (channel+0 >= 36) band = 5
					else if (channel+0 > 0) band = 24
					printf "%s|%s|%s|%s|%s\n", band, channel, signal, enc, ssid
				}
			}
		' >> "$tmp" || true
	done
	awk -F'|' '
		NF < 5 { next }
		{
			ssid=$5
			for (i=6;i<=NF;i++) ssid=ssid "|" $i
			if (ssid == "" || ssid ~ /^Travel-VPN/ || ssid == "OpenWrt" || ssid == "unknown") next
			key=$1 SUBSEP ssid
			if (key in seen) next
			seen[key]=1
			sig=$3+0
			printf "%s|%s|%s|%s|%s\n", $1, $2, sig, $4, ssid
		}
	' "$tmp" | sort -t'|' -k3,3nr
	rm -f "$tmp"
}

lookup_scan_row() {
	ssid="$1"
	cmd_scan | awk -F'|' -v s="$ssid" '
		{
			name=$5
			for (i=6;i<=NF;i++) name=name "|" $i
			if (name == s) { print $0; exit }
		}
	'
}

cmd_apply() {
	ssid=${WISP_SSID:-${2:-}}
	key=${WISP_KEY:-}
	band=${WISP_BAND:-${1:-auto}}
	enc_hint=${WISP_ENC:-}

	if [ -z "$key" ] && [ ! -t 0 ]; then
		key=$(cat)
	fi

	if [ -z "$ssid" ]; then
		ssid=${WISP_SSID:-}
		band=${WISP_BAND:-auto}
	fi

	if [ -z "$ssid" ]; then
		echo "Нужен SSID" >&2
		exit 1
	fi

	row=$(lookup_scan_row "$ssid" || true)
	if [ -n "$row" ]; then
		row_band=$(echo "$row" | cut -d'|' -f1)
		row_enc=$(echo "$row" | cut -d'|' -f4)
		[ "$band" = auto ] || [ -z "$band" ] && band=$row_band
		[ -z "$enc_hint" ] && enc_hint=$row_enc
	fi

	case "$band" in
		5|5g|5G) sta=$STA5; iface=$IF5; band=5 ;;
		24|2.4|2g|2G|24g) sta=$STA24; iface=$IF24; band=24 ;;
		*)
			echo "Не удалось определить диапазон для «${ssid}». Выберите сеть из списка или укажите 5 / 2.4 ГГц." >&2
			exit 1
			;;
	esac

	enc_uci=$(enc_from_scan "${enc_hint:-psk2}")

	uci set "wireless.${sta}.ssid=${ssid}"
	uci set "wireless.${sta}.key=${key}"
	uci set "wireless.${sta}.encryption=${enc_uci}"
	uci set "wireless.${sta}.disabled=0"
	uci commit wireless

	wifi reload

	(
		i=0
		while [ "$i" -lt 40 ]; do
			if ifstatus "$iface" 2>/dev/null | grep -q '"up": true'; then
				break
			fi
			i=$((i + 1))
			sleep 1
		done
		if [ -x "$HOTPLUG" ]; then
			INTERFACE="$iface" ACTION=ifup "$HOTPLUG" || true
		fi
		sleep 2
		hs=$(awg show wg0 latest-handshakes 2>/dev/null | awk 'NR==1 {print $2; exit}')
		hs=${hs:-0}
		if [ "$hs" = "0" ] || ! ip link show wg0 >/dev/null 2>&1; then
			ifup wg0 2>/dev/null || true
			sleep 3
			[ -x "$HOTPLUG" ] && INTERFACE="$iface" ACTION=ifup "$HOTPLUG" || true
		fi
		logger -t wisp-switch "background done ssid=${ssid} iface=${iface}"
	) >/dev/null 2>&1 &

	echo "applied_ssid=${ssid}"
	echo "applied_band=${band}"
	echo "applied_iface=${iface}"
	cmd_status
}

case "${1:-}" in
	scan) cmd_scan ;;
	status) cmd_status ;;
	apply) shift; cmd_apply "$@" ;;
	*)
		echo "usage: $0 scan|status|apply" >&2
		exit 1
		;;
esac
