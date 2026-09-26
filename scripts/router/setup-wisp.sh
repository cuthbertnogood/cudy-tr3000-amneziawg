#!/bin/sh
# Cudy TR3000 (OpenWrt): два WISP-клиента + AP Travel-VPN.
# Запускать ДО awg-apply.sh (нужен uplink для handshake).
#
#   WISP5_SSID=... WISP24_SSID=... WISP_KEY=... AP_KEY=... sh setup-wisp.sh
#
set -eu

WISP5_SSID="${WISP5_SSID:-UPLINK_5}"
WISP24_SSID="${WISP24_SSID:-UPLINK_24}"
WISP5_KEY="${WISP5_KEY:-${WISP_KEY:-}}"
WISP24_KEY="${WISP24_KEY:-${WISP_KEY:-}}"
LAN_IP="${LAN_IP:-192.168.10.1}"
AP24_SSID="${AP24_SSID:-Travel-VPN-2.4G}"
AP5_SSID="${AP5_SSID:-Travel-VPN-5G}"
AP_KEY="${AP_KEY:-}"
RADIO5="${RADIO5:-radio1}"
RADIO24="${RADIO24:-radio0}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" 2>/dev/null && pwd || echo /tmp)"

if [ -z "${WISP5_KEY}" ] || [ -z "${WISP24_KEY}" ]; then
  echo "Нужен WISP_KEY=... (или WISP5_KEY / WISP24_KEY) — пароль uplink Wi‑Fi" >&2
  exit 1
fi
if [ -z "${AP_KEY}" ]; then
  echo "Нужен AP_KEY=... — пароль сетей Travel-VPN для клиентов" >&2
  exit 1
fi

echo "== LAN ${LAN_IP} =="
uci set network.lan.ipaddr="${LAN_IP}"
uci set network.lan.netmask='255.255.255.0'
uci commit network

echo "== WISP 5 ГГц ${WISP5_SSID} → wwan5 metric 10 =="
uci -q delete wireless.sta_wisp || true
uci -q delete wireless.sta_wisp5 || true
uci set wireless.sta_wisp5=wifi-iface
uci set wireless.sta_wisp5.device="${RADIO5}"
uci set wireless.sta_wisp5.mode='sta'
uci set wireless.sta_wisp5.network='wwan5'
uci set wireless.sta_wisp5.ssid="${WISP5_SSID}"
uci set wireless.sta_wisp5.encryption='psk2'
uci set wireless.sta_wisp5.key="${WISP5_KEY}"
uci set wireless.sta_wisp5.disabled='0'

uci -q delete network.wwan || true
uci -q delete network.wwan5 || true
uci set network.wwan5=interface
uci set network.wwan5.proto='dhcp'
uci set network.wwan5.metric='10'
uci set network.wwan5.defaultroute='0'
uci set network.wwan5.peerdns='0'

echo "== WISP 2,4 ГГц ${WISP24_SSID} → wwan24 metric 20 =="
uci -q delete wireless.sta_wisp24 || true
uci set wireless.sta_wisp24=wifi-iface
uci set wireless.sta_wisp24.device="${RADIO24}"
uci set wireless.sta_wisp24.mode='sta'
uci set wireless.sta_wisp24.network='wwan24'
uci set wireless.sta_wisp24.ssid="${WISP24_SSID}"
uci set wireless.sta_wisp24.encryption='psk2'
uci set wireless.sta_wisp24.key="${WISP24_KEY}"
uci set wireless.sta_wisp24.disabled='0'

uci -q delete network.wwan24 || true
uci set network.wwan24=interface
uci set network.wwan24.proto='dhcp'
uci set network.wwan24.metric='20'
uci set network.wwan24.defaultroute='0'
uci set network.wwan24.peerdns='0'

uci set wireless.${RADIO5}.disabled='0'
uci set wireless.${RADIO24}.disabled='0'
uci commit wireless
uci commit network

echo "== AP Travel-VPN =="
uci -q delete wireless.ap24 || true
uci set wireless.ap24=wifi-iface
uci set wireless.ap24.device="${RADIO24}"
uci set wireless.ap24.mode='ap'
uci set wireless.ap24.network='lan'
uci set wireless.ap24.ssid="${AP24_SSID}"
uci set wireless.ap24.encryption='psk2'
uci set wireless.ap24.key="${AP_KEY}"
uci set wireless.ap24.disabled='0'

uci -q delete wireless.ap5 || true
uci set wireless.ap5=wifi-iface
uci set wireless.ap5.device="${RADIO5}"
uci set wireless.ap5.mode='ap'
uci set wireless.ap5.network='lan'
uci set wireless.ap5.ssid="${AP5_SSID}"
uci set wireless.ap5.encryption='psk2'
uci set wireless.ap5.key="${AP_KEY}"
uci set wireless.ap5.disabled='0'
uci commit wireless

echo "== firewall: wwan5 + wwan24 в зону wan =="
for net in wwan wwan5 wwan24; do
  uci -q del_list firewall.@zone[1].network="${net}" 2>/dev/null || true
done
uci add_list firewall.@zone[1].network='wwan5'
uci add_list firewall.@zone[1].network='wwan24'
uci commit firewall

echo "== Wi‑Fi reload =="
wifi reload
/etc/init.d/network reload
sleep 12

echo "== hotplug endpoint =="
if [ -f "${SCRIPT_DIR}/wwan-endpoint-route.sh" ]; then
  sh "${SCRIPT_DIR}/wwan-endpoint-route.sh" --install
elif [ -f /tmp/wwan-endpoint-route.sh ]; then
  sh /tmp/wwan-endpoint-route.sh --install
fi

echo ""
ip -4 addr show | awk '/^[0-9]+: (phy|br-)/{iface=$2} /inet /{print iface,$2}'
echo ""
ip -4 route
echo ""
echo "Дальше: awg-apply.sh (после настройки VPS и WG_ENDPOINT)"
