#!/bin/sh
# Скан и смена WISP (чужой Wi‑Fi) на Cudy. Вызывается из LuCI-страницы.
#
#   wisp-switch.sh status|scan|scan-start|scan-poll
#   WISP_MODE=both|5|24 wisp-switch.sh set-mode
#   WISP_SSID=... WISP_KEY=... WISP_BAND=5|24 WISP_MODE=both|5|24 wisp-switch.sh apply
#
set -eu

STA5="${STA5:-sta_wisp5}"
STA24="${STA24:-sta_wisp24}"
IF5="${IF5:-wwan5}"
IF24="${IF24:-wwan24}"
ENDPOINT="${WG_ENDPOINT:-}"
if [ -z "$ENDPOINT" ] && [ -f /etc/amnezia/endpoint ]; then
	ENDPOINT=$(head -n1 /etc/amnezia/endpoint | tr -d ' \t\r\n')
fi
if [ -z "$ENDPOINT" ]; then
	ENDPOINT=$(uci -q get network.wgvps.endpoint_host 2>/dev/null || true)
fi
if [ -z "$ENDPOINT" ]; then
	ENDPOINT=$(uci -q get network.wgserver.endpoint_host 2>/dev/null || true)
fi
HOTPLUG="${HOTPLUG:-/etc/hotplug.d/iface/99-awg-endpoint}"
SCAN_OUT="${SCAN_OUT:-/tmp/wisp-scan.out}"
SCAN_STATE="${SCAN_STATE:-/tmp/wisp-scan.state}"
SCAN_ERR="${SCAN_ERR:-/tmp/wisp-scan.err}"
MODE_FILE="${MODE_FILE:-/etc/amnezia/wisp-mode}"

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

read_mode() {
	m=$(cat "${MODE_FILE}" 2>/dev/null || true)
	case "$m" in
		both|5|24) echo "$m" ;;
		*)
			d5=$(uci -q get "wireless.${STA5}.disabled" 2>/dev/null || echo 0)
			d24=$(uci -q get "wireless.${STA24}.disabled" 2>/dev/null || echo 0)
			if [ "$d5" = 1 ] && [ "$d24" != 1 ]; then echo 24
			elif [ "$d24" = 1 ] && [ "$d5" != 1 ]; then echo 5
			else echo both
			fi
			;;
	esac
}

write_mode() {
	mkdir -p "$(dirname "${MODE_FILE}")"
	echo "$1" > "${MODE_FILE}"
}

ensure_sta() {
	name="$1"
	device="$2"
	network="$3"
	ssid_default="$4"
	if uci -q get "wireless.${name}" >/dev/null 2>&1; then
		return 0
	fi
	uci set "wireless.${name}=wifi-iface"
	uci set "wireless.${name}.device=${device}"
	uci set "wireless.${name}.mode=sta"
	uci set "wireless.${name}.network=${network}"
	uci set "wireless.${name}.ssid=${ssid_default}"
	uci set "wireless.${name}.encryption=psk2"
	uci set "wireless.${name}.key=${WISP_KEY:-changeme}"
	uci set "wireless.${name}.disabled=1"
}

ensure_stas() {
	ensure_sta "${STA5}" radio1 "${IF5}" 'UPLINK_5'
	ensure_sta "${STA24}" radio0 "${IF24}" 'UPLINK_24'
}

apply_mode_flags() {
	mode="$1"
	ensure_stas
	case "$mode" in
		5)
			uci set "wireless.${STA5}.disabled=0"
			uci set "wireless.${STA24}.disabled=1"
			;;
		24)
			uci set "wireless.${STA5}.disabled=1"
			uci set "wireless.${STA24}.disabled=0"
			;;
		both)
			uci set "wireless.${STA5}.disabled=0"
			uci set "wireless.${STA24}.disabled=0"
			;;
		*)
			echo "Режим: both|5|24" >&2
			return 1
			;;
	esac
	write_mode "$mode"
	uci commit wireless
}

traffic_mode() {
	m=$(cat /etc/amnezia/traffic-mode 2>/dev/null || echo vpn)
	case "$m" in
		wisp) echo wisp ;;
		*) echo vpn ;;
	esac
}

bg_bringup() {
	iface="$1"
	(
		i=0
		while [ "$i" -lt 40 ]; do
			if ifstatus "$iface" 2>/dev/null | grep -q '"up": true'; then
				break
			fi
			i=$((i + 1))
			sleep 1
		done
		tm=$(traffic_mode)
		if [ "$tm" = vpn ] && [ -x "$HOTPLUG" ]; then
			INTERFACE="$iface" ACTION=ifup "$HOTPLUG" || true
		fi
		if [ "$tm" = vpn ]; then
			sleep 2
			hs=$(awg show wg0 latest-handshakes 2>/dev/null | awk 'NR==1 {print $2; exit}')
			hs=${hs:-0}
			if [ "$hs" = "0" ] || ! ip link show wg0 >/dev/null 2>&1; then
				ifup wg0 2>/dev/null || true
				sleep 3
				[ -x "$HOTPLUG" ] && INTERFACE="$iface" ACTION=ifup "$HOTPLUG" || true
			fi
		fi
		logger -t wisp-switch "bringup iface=${iface} traffic=${tm}"
	) >/dev/null 2>&1 &
}

cmd_status() {
	ssid5=$(uci -q get "wireless.${STA5}.ssid" 2>/dev/null || true)
	ssid24=$(uci -q get "wireless.${STA24}.ssid" 2>/dev/null || true)
	dis5=$(uci -q get "wireless.${STA5}.disabled" 2>/dev/null || echo 0)
	dis24=$(uci -q get "wireless.${STA24}.disabled" 2>/dev/null || echo 0)
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
	mode=$(read_mode)
	printf 'ssid5=%s\n' "$ssid5"
	printf 'ssid24=%s\n' "$ssid24"
	printf 'dis5=%s\n' "${dis5:-0}"
	printf 'dis24=%s\n' "${dis24:-0}"
	printf 'up5=%s\n' "$up5"
	printf 'up24=%s\n' "$up24"
	printf 'mode=%s\n' "$mode"
	printf 'traffic=%s\n' "$(traffic_mode)"
	printf 'tunnel=%s\n' "$tunnel"
	printf 'handshake_age=%s\n' "$age"
}

cmd_set_mode() {
	mode=${WISP_MODE:-${1:-}}
	case "$mode" in
		5|24|both) ;;
		*)
			echo "Нужен режим: both | 5 | 24" >&2
			exit 1
			;;
	esac
	apply_mode_flags "$mode"
	wifi reload
	case "$mode" in
		5) bg_bringup "$IF5" ;;
		24) bg_bringup "$IF24" ;;
		both) bg_bringup "$IF5"; bg_bringup "$IF24" ;;
	esac
	echo "applied_mode=${mode}"
	cmd_status
}

# Строки: band|channel|signal|enc|ssid
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

cmd_scan_start() {
	st=$(cat "${SCAN_STATE}" 2>/dev/null || echo idle)
	if [ "$st" = running ]; then
		pid=$(cat /tmp/wisp-scan.pid 2>/dev/null || true)
		if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
			echo 'state=running'
			return 0
		fi
	fi
	rm -f "${SCAN_OUT}" "${SCAN_ERR}" "${SCAN_OUT}.tmp"
	echo running > "${SCAN_STATE}"

	if command -v start-stop-daemon >/dev/null 2>&1; then
		start-stop-daemon -K -q -p /tmp/wisp-scan.pid 2>/dev/null || true
		start-stop-daemon -S -b -m -p /tmp/wisp-scan.pid -x /bin/sh -- \
			/usr/libexec/wisp-scan-worker.sh
	else
		/bin/sh -c "exec /usr/libexec/wisp-scan-worker.sh" </dev/null >/dev/null 2>&1 &
		echo $! > /tmp/wisp-scan.pid
	fi
	echo 'state=running'
}

cmd_scan_poll() {
	st=$(cat "${SCAN_STATE}" 2>/dev/null || echo idle)
	echo "state=${st}"
	case "$st" in
		done)
			[ -f "${SCAN_OUT}" ] && cat "${SCAN_OUT}"
			;;
		error)
			[ -f "${SCAN_ERR}" ] && sed 's/^/err=/' "${SCAN_ERR}" | head -5
			;;
	esac
}

lookup_scan_row() {
	ssid="$1"
	# без полного перескана: из последнего результата
	if [ -f "${SCAN_OUT}" ]; then
		awk -F'|' -v s="$ssid" '
			{
				name=$5
				for (i=6;i<=NF;i++) name=name "|" $i
				if (name == s) { print $0; exit }
			}
		' "${SCAN_OUT}"
	fi
}

cmd_apply() {
	ssid=${WISP_SSID:-${2:-}}
	key=${WISP_KEY:-}
	band=${WISP_BAND:-${1:-auto}}
	enc_hint=${WISP_ENC:-}
	mode=${WISP_MODE:-}

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
			echo "Не удалось определить диапазон для «${ssid}»." >&2
			exit 1
			;;
	esac

	# Режим: явный WISP_MODE, иначе «только этот диапазон» при подключении к сети
	case "$mode" in
		5|24|both) ;;
		*) mode=$band ;;
	esac

	enc_uci=$(enc_from_scan "${enc_hint:-psk2}")

	uci set "wireless.${sta}.ssid=${ssid}"
	uci set "wireless.${sta}.key=${key}"
	uci set "wireless.${sta}.encryption=${enc_uci}"
	uci set "wireless.${sta}.disabled=0"
	apply_mode_flags "$mode"

	wifi reload
	bg_bringup "$iface"

	echo "applied_ssid=${ssid}"
	echo "applied_band=${band}"
	echo "applied_mode=${mode}"
	echo "applied_iface=${iface}"
	cmd_status
}

case "${1:-}" in
	scan) cmd_scan ;;
	scan-start) cmd_scan_start ;;
	scan-poll) cmd_scan_poll ;;
	status) cmd_status ;;
	set-mode) shift; cmd_set_mode "$@" ;;
	apply) shift; cmd_apply "$@" ;;
	*)
		echo "usage: $0 status|scan|scan-start|scan-poll|set-mode|apply" >&2
		exit 1
		;;
esac
