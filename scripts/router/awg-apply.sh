#!/bin/sh
# Cudy TR3000 (OpenWrt 24.10): AmneziaWG-клиент wg0 + kill-switch.
#
#   1) WG_ENDPOINT=VPS_IP sh awg-apply.sh          # ключи / CLIENT_PUB для VPS
#   2) AWG_SERVER_PUBKEY=... WG_ENDPOINT=VPS_IP sh awg-apply.sh
#
# Переиспользовать ключ: /etc/wireguard/wg0.key или ROUTER_WG_PRIVATE_KEY=...
#
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" 2>/dev/null && pwd || echo /tmp)"
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/awg-params.env" ] && . "${SCRIPT_DIR}/awg-params.env"

WG_IF="${WG_IF:-wg0}"
WG_ADDR="${WG_ADDR:-10.9.0.2/24}"
WG_MTU="${WG_MTU:-1280}"
WG_ENDPOINT="${WG_ENDPOINT:-}"
WG_PORT="${WG_PORT:-443}"
WG_KEEPALIVE="${WG_KEEPALIVE:-25}"
LAN_IP="${LAN_IP:-192.168.10.1}"
WISP_IFACES="${WISP_IFACES:-wwan5 wwan24}"
KEYDIR="/etc/wireguard"
KMOD_KO="${KMOD_KO:-/lib/modules/$(uname -r)/amneziawg.ko}"
HOTPLUG_SRC="${HOTPLUG_SRC:-${SCRIPT_DIR}/wwan-endpoint-route.sh}"
[ -f "${HOTPLUG_SRC}" ] || HOTPLUG_SRC="/tmp/wwan-endpoint-route.sh"

AWG_JC="${AWG_JC:-4}"
AWG_JMIN="${AWG_JMIN:-40}"
AWG_JMAX="${AWG_JMAX:-70}"
AWG_S1="${AWG_S1:-0}"
AWG_S2="${AWG_S2:-0}"
AWG_H1="${AWG_H1:-1}"
AWG_H2="${AWG_H2:-2}"
AWG_H3="${AWG_H3:-3}"
AWG_H4="${AWG_H4:-4}"

PKG_MGR=""
if command -v opkg >/dev/null 2>&1; then
  PKG_MGR=opkg
elif command -v apk >/dev/null 2>&1; then
  PKG_MGR=apk
fi

echo "== снять wireguard/amneziawg =="
ifdown "${WG_IF}" 2>/dev/null || true

echo "== пакеты AmneziaWG (${PKG_MGR:-none}) =="
if ! command -v awg >/dev/null 2>&1; then
  TOOLS_IPK="${TOOLS_IPK:-/tmp/amneziawg-tools.ipk}"
  TOOLS_APK="${TOOLS_APK:-/tmp/amneziawg-tools.apk}"
  if [ -f "${TOOLS_IPK}" ] && [ "${PKG_MGR}" = opkg ]; then
    opkg install ip-full 2>/dev/null || true
    opkg install "${TOOLS_IPK}" 2>/dev/null || opkg install --force-depends "${TOOLS_IPK}"
  elif [ -f "${TOOLS_APK}" ] && [ "${PKG_MGR}" = apk ]; then
    apk add --allow-untrusted ip-full 2>/dev/null || true
    apk add --allow-untrusted "${TOOLS_APK}" 2>/dev/null || true
  elif [ "${PKG_MGR}" = opkg ]; then
    opkg update 2>/dev/null || true
    opkg install amneziawg-tools ip-full 2>/dev/null || true
  elif [ "${PKG_MGR}" = apk ]; then
    apk update 2>/dev/null || true
    apk add amneziawg-tools ip-full 2>/dev/null || true
  fi
fi

if [ ! -e /sys/module/amneziawg ]; then
  if [ -f "${KMOD_KO}" ]; then
    echo "  insmod ${KMOD_KO}"
    insmod "${KMOD_KO}" 2>/dev/null || modprobe amneziawg 2>/dev/null || true
  else
    KMOD_IPK="${KMOD_IPK:-/tmp/kmod-amneziawg.ipk}"
    if [ -f "${KMOD_IPK}" ] && [ "${PKG_MGR}" = opkg ]; then
      opkg install "${KMOD_IPK}" 2>/dev/null || opkg install --force-depends "${KMOD_IPK}"
    fi
  fi
  [ ! -e /sys/module/amneziawg ] && modprobe amneziawg 2>/dev/null || true
fi

if [ ! -e /sys/module/amneziawg ]; then
  echo "ОШИБКА: kmod amneziawg не загружен. Положите .ko в ${KMOD_KO}" >&2
  exit 1
fi

if [ "${PKG_MGR}" = opkg ] && opkg list-installed 2>/dev/null | grep -q kmod-wireguard; then
  opkg remove kmod-wireguard wireguard-tools 2>/dev/null || true
elif [ "${PKG_MGR}" = apk ] && apk list --installed 2>/dev/null | grep -q kmod-wireguard; then
  apk del kmod-wireguard wireguard-tools 2>/dev/null || true
fi

echo "== автозагрузка kmod =="
echo amneziawg > /etc/modules.d/99-amneziawg 2>/dev/null || true

echo "== ключи клиента =="
mkdir -p "$KEYDIR"
chmod 700 "$KEYDIR"
if [ -n "${ROUTER_WG_PRIVATE_KEY:-}" ]; then
  printf '%s\n' "${ROUTER_WG_PRIVATE_KEY}" > "${KEYDIR}/${WG_IF}.key"
  chmod 600 "${KEYDIR}/${WG_IF}.key"
elif [ ! -s "${KEYDIR}/${WG_IF}.key" ]; then
  awg genkey > "${KEYDIR}/${WG_IF}.key"
  chmod 600 "${KEYDIR}/${WG_IF}.key"
fi
awg pubkey < "${KEYDIR}/${WG_IF}.key" > "${KEYDIR}/${WG_IF}.pub"
CLIENT_PRIV="$(cat "${KEYDIR}/${WG_IF}.key")"
CLIENT_PUB="$(cat "${KEYDIR}/${WG_IF}.pub")"

if [ -z "${AWG_SERVER_PUBKEY:-}" ]; then
  echo ""
  echo "Публичный ключ клиента (CLIENT_PUB на VPS):"
  echo "  ${CLIENT_PUB}"
  echo ""
  echo "Дальше на VPS: CLIENT_PUB='...' sh awg-server.sh"
  echo "Затем на роутере: AWG_SERVER_PUBKEY=<ключ сервера> WG_ENDPOINT=<VPS_IP> sh awg-apply.sh"
  exit 0
fi

if [ -z "${WG_ENDPOINT}" ]; then
  echo "Задайте WG_ENDPOINT=<публичный IP VPS>" >&2
  exit 1
fi

echo "== host-route endpoint через лучший WISP =="
if [ -f "${HOTPLUG_SRC}" ]; then
  WG_ENDPOINT="${WG_ENDPOINT}" sh "${HOTPLUG_SRC}" --install
else
  echo "WARN: ${HOTPLUG_SRC} нет — host-route поставит setup-wisp / hotplug вручную"
fi

echo "== интерфейс ${WG_IF} (proto amneziawg) =="
uci -q delete network.${WG_IF} || true
uci set network.${WG_IF}=interface
uci set network.${WG_IF}.proto='amneziawg'
uci set network.${WG_IF}.private_key="${CLIENT_PRIV}"
uci add_list network.${WG_IF}.addresses="${WG_ADDR}"
uci set network.${WG_IF}.mtu="${WG_MTU}"
uci set network.${WG_IF}.awg_jc="${AWG_JC}"
uci set network.${WG_IF}.awg_jmin="${AWG_JMIN}"
uci set network.${WG_IF}.awg_jmax="${AWG_JMAX}"
uci set network.${WG_IF}.awg_s1="${AWG_S1}"
uci set network.${WG_IF}.awg_s2="${AWG_S2}"
uci set network.${WG_IF}.awg_h1="${AWG_H1}"
uci set network.${WG_IF}.awg_h2="${AWG_H2}"
uci set network.${WG_IF}.awg_h3="${AWG_H3}"
uci set network.${WG_IF}.awg_h4="${AWG_H4}"

uci -q delete network.wgvps || true
uci set network.wgvps="amneziawg_${WG_IF}"
uci set network.wgvps.description='vps'
uci set network.wgvps.public_key="${AWG_SERVER_PUBKEY}"
uci set network.wgvps.endpoint_host="${WG_ENDPOINT}"
uci set network.wgvps.endpoint_port="${WG_PORT}"
uci add_list network.wgvps.allowed_ips='0.0.0.0/0'
uci set network.wgvps.route_allowed_ips='1'
uci set network.wgvps.persistent_keepalive="${WG_KEEPALIVE}"
uci commit network

echo "== firewall: зона wg, lan -> wg, kill-switch =="
uci -q delete firewall.wgzone || true
uci set firewall.wgzone=zone
uci set firewall.wgzone.name='wg'
uci set firewall.wgzone.network="${WG_IF}"
uci set firewall.wgzone.input='REJECT'
uci set firewall.wgzone.output='ACCEPT'
uci set firewall.wgzone.forward='REJECT'
uci set firewall.wgzone.masq='1'
uci set firewall.wgzone.mtu_fix='1'

i=0
while uci -q get "firewall.@forwarding[$i]" >/dev/null 2>&1; do
  src="$(uci -q get "firewall.@forwarding[$i].src" || echo '')"
  dst="$(uci -q get "firewall.@forwarding[$i].dest" || echo '')"
  case "${dst}" in
    wan|wwan|wwan5|wwan24)
      if [ "${src}" = 'lan' ]; then
        uci delete "firewall.@forwarding[$i]"
        continue
      fi
      ;;
  esac
  i=$((i + 1))
done

for net in ${WISP_IFACES} wwan; do
  uci -q del_list firewall.@zone[1].network="${net}" 2>/dev/null || true
done
for net in ${WISP_IFACES}; do
  uci add_list firewall.@zone[1].network="${net}"
done
uci commit firewall

uci -q delete firewall.lan_wg || true
uci set firewall.lan_wg=forwarding
uci set firewall.lan_wg.src='lan'
uci set firewall.lan_wg.dest='wg'
uci commit firewall

echo "== DHCP на LAN =="
uci set dhcp.lan.ignore='0'
uci set dhcp.lan.start='100'
uci set dhcp.lan.limit='50'
uci set dhcp.lan.leasetime='12h'
uci -q delete dhcp.lan.dhcp_option || true
uci add_list dhcp.lan.dhcp_option="3,${LAN_IP}"
uci add_list dhcp.lan.dhcp_option="6,${LAN_IP}"
uci commit dhcp

echo "== DNS через туннель, не через WISP =="
uci set dhcp.@dnsmasq[0].noresolv='1'
uci -q delete dhcp.@dnsmasq[0].server
uci add_list dhcp.@dnsmasq[0].server='1.1.1.1'
uci add_list dhcp.@dnsmasq[0].server='1.0.0.1'
uci commit dhcp

echo "== применяем =="
/etc/init.d/network reload
sleep 8
/etc/init.d/firewall reload >/dev/null 2>&1 || true
/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
if [ -f "${HOTPLUG_SRC}" ]; then
  INTERFACE=wwan5 ACTION=ifup WG_ENDPOINT="${WG_ENDPOINT}" sh "${HOTPLUG_SRC}" 2>/dev/null || true
fi
sleep 3

echo ""
echo "== состояние =="
awg show 2>/dev/null || true
echo ""
ip -4 route get "${WG_ENDPOINT}" 2>/dev/null || true
ip -4 route
echo ""
echo "Проверка: wget -qO- http://ifconfig.me  # ожидаем IP VPS (${WG_ENDPOINT})"
echo "Hotplug: /etc/hotplug.d/iface/99-awg-endpoint"
