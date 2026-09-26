#!/bin/sh
# VPS (Ubuntu/Debian): AmneziaWG-сервер wg0, один пир — Cudy TR3000.
# Чистый wg-quick@wg0 снимается. Параметры маскировки — из awg-params.env.
#
#   CLIENT_PUB='<pubkey с роутера>' sudo -E sh awg-server.sh
#   sudo sh awg-server.sh   # CLIENT_PUB из /etc/amnezia/amneziawg/clients/cudy.pub
#
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/awg-params.env" ] && . "${SCRIPT_DIR}/awg-params.env"

WG_IF="${WG_IF:-wg0}"
WG_PORT="${WG_PORT:-443}"
WG_ADDR="${WG_ADDR:-10.9.0.1/24}"
WG_NET="${WG_NET:-10.9.0.0/24}"
CLIENT_IP="${CLIENT_IP:-10.9.0.2/32}"
EXT_IF="${EXT_IF:-eth0}"
CONF_DIR="/etc/amnezia/amneziawg"
CLIENT_DIR="${CONF_DIR}/clients"

AWG_JC="${AWG_JC:-4}"
AWG_JMIN="${AWG_JMIN:-40}"
AWG_JMAX="${AWG_JMAX:-70}"
AWG_S1="${AWG_S1:-0}"
AWG_S2="${AWG_S2:-0}"
AWG_H1="${AWG_H1:-1}"
AWG_H2="${AWG_H2:-2}"
AWG_H3="${AWG_H3:-3}"
AWG_H4="${AWG_H4:-4}"

if [ -z "${CLIENT_PUB:-}" ] && [ -f "${CLIENT_DIR}/cudy.pub" ]; then
  CLIENT_PUB="$(cat "${CLIENT_DIR}/cudy.pub")"
fi
if [ -z "${CLIENT_PUB:-}" ]; then
  echo "Нужен CLIENT_PUB=<pubkey Cudy> или ${CLIENT_DIR}/cudy.pub" >&2
  echo "Сначала на роутере: sh awg-apply.sh — скопируйте выведенный CLIENT_PUB." >&2
  exit 1
fi

if [ -z "${EXT_IF:-}" ] || ! ip link show "${EXT_IF}" >/dev/null 2>&1; then
  for cand in eth0 ens3 enp0s3; do
    if ip link show "${cand}" >/dev/null 2>&1; then
      EXT_IF="${cand}"
      break
    fi
  done
fi

echo "== снять чистый WireGuard =="
systemctl stop "wg-quick@${WG_IF}" 2>/dev/null || true
systemctl disable "wg-quick@${WG_IF}" 2>/dev/null || true
systemctl mask "wg-quick@${WG_IF}" 2>/dev/null || true
if [ -f "/etc/wireguard/${WG_IF}.conf" ]; then
  mv "/etc/wireguard/${WG_IF}.conf" "/etc/wireguard/${WG_IF}.conf.wg-bak"
fi

echo "== amneziawg (PPA) =="
if ! modinfo amneziawg >/dev/null 2>&1; then
  if ! grep -q 'deb-src' /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null; then
    sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources
  fi
  apt-get update -qq
  apt-get install -y -qq software-properties-common gnupg2 "linux-headers-$(uname -r)"
  add-apt-repository -y ppa:amnezia/ppa || true
  apt-get update -qq
  apt-get install -y -qq amneziawg || {
    echo "PPA amnezia/ppa недоступен для $(lsb_release -cs), пробуем noble..." >&2
    echo "deb https://ppa.launchpadcontent.net/amnezia/ppa/ubuntu noble main" > /etc/apt/sources.list.d/amnezia-ppa.list
    echo "deb-src https://ppa.launchpadcontent.net/amnezia/ppa/ubuntu noble main" >> /etc/apt/sources.list.d/amnezia-ppa.list
    apt-get update -qq
    apt-get install -y -qq amneziawg
  }
fi
modprobe amneziawg 2>/dev/null || true

echo "== ключи сервера =="
mkdir -p "${CONF_DIR}" "${CLIENT_DIR}"
chmod 700 "${CONF_DIR}" "${CLIENT_DIR}"
if [ ! -s "${CONF_DIR}/${WG_IF}.key" ]; then
  awg genkey > "${CONF_DIR}/${WG_IF}.key"
  chmod 600 "${CONF_DIR}/${WG_IF}.key"
  awg pubkey < "${CONF_DIR}/${WG_IF}.key" > "${CONF_DIR}/${WG_IF}.pub"
fi
SERVER_PRIV="$(cat "${CONF_DIR}/${WG_IF}.key")"
SERVER_PUB="$(cat "${CONF_DIR}/${WG_IF}.pub")"
echo "${CLIENT_PUB}" > "${CLIENT_DIR}/cudy.pub"

echo "== ip_forward =="
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-amneziawg.conf
sysctl -q -w net.ipv4.ip_forward=1

echo "== ${CONF_DIR}/${WG_IF}.conf =="
cat > "${CONF_DIR}/${WG_IF}.conf" <<EOF
[Interface]
Address = ${WG_ADDR}
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIV}
Jc = ${AWG_JC}
Jmin = ${AWG_JMIN}
Jmax = ${AWG_JMAX}
S1 = ${AWG_S1}
S2 = ${AWG_S2}
H1 = ${AWG_H1}
H2 = ${AWG_H2}
H3 = ${AWG_H3}
H4 = ${AWG_H4}

PostUp = iptables -t nat -C POSTROUTING -s ${WG_NET} -o ${EXT_IF} -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s ${WG_NET} -o ${EXT_IF} -j MASQUERADE
PostUp = iptables -C FORWARD -i %i -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -i %i -j ACCEPT
PostUp = iptables -C FORWARD -o %i -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -o %i -j ACCEPT

PostDown = iptables -t nat -D POSTROUTING -s ${WG_NET} -o ${EXT_IF} -j MASQUERADE 2>/dev/null || true
PostDown = iptables -D FORWARD -i %i -j ACCEPT 2>/dev/null || true
PostDown = iptables -D FORWARD -o %i -j ACCEPT 2>/dev/null || true

[Peer]
# cudy-tr3000
PublicKey = ${CLIENT_PUB}
AllowedIPs = ${CLIENT_IP}
EOF
chmod 600 "${CONF_DIR}/${WG_IF}.conf"

if [ -f /etc/apparmor.d/wg-quick ] && ! grep -q net_bind_service /etc/apparmor.d/wg-quick; then
  sed -i '/^}/i\  capability net_bind_service,' /etc/apparmor.d/wg-quick 2>/dev/null || true
  systemctl reload apparmor 2>/dev/null || true
fi

echo "== firewall =="
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
  ufw allow "${WG_PORT}/udp" >/dev/null 2>&1 || true
  ufw route allow in on "${WG_IF}" >/dev/null 2>&1 || true
fi

echo "== awg-quick@${WG_IF} =="
systemctl enable "awg-quick@${WG_IF}" >/dev/null 2>&1 || true
systemctl restart "awg-quick@${WG_IF}"
sleep 2

echo ""
awg show "${WG_IF}" || true
echo ""
echo "Публичный ключ сервера (AWG_SERVER_PUBKEY на роутере):"
echo "  ${SERVER_PUB}"
echo ""
echo "Endpoint для клиента: <VPS_IP>:${WG_PORT}/udp"
ss -ulnp | grep ":${WG_PORT}" || echo "ВНИМАНИЕ: UDP ${WG_PORT} не слушается — проверьте firewall провайдера VPS"
