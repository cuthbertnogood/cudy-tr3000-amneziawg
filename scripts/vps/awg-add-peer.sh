#!/bin/sh
# VPS: добавить или обновить пир Cudy в существующем awg0 без пересоздания ключа сервера.
#
#   CLIENT_PUB='<pubkey>' sudo -E sh awg-add-peer.sh
#
set -eu

WG_IF="${WG_IF:-wg0}"
CLIENT_IP="${CLIENT_IP:-10.9.0.2/32}"
CONF_DIR="/etc/amnezia/amneziawg"
CONF="${CONF_DIR}/${WG_IF}.conf"
CLIENT_DIR="${CONF_DIR}/clients"

if [ -z "${CLIENT_PUB:-}" ]; then
  if [ -f "${CLIENT_DIR}/cudy.pub" ]; then
    CLIENT_PUB="$(cat "${CLIENT_DIR}/cudy.pub")"
  else
    echo "Нужен CLIENT_PUB=<pubkey Cudy> или ${CLIENT_DIR}/cudy.pub" >&2
    exit 1
  fi
fi

if [ ! -s "${CONF}" ]; then
  echo "Нет ${CONF} — сначала запустите awg-server.sh" >&2
  exit 1
fi

mkdir -p "${CLIENT_DIR}"
echo "${CLIENT_PUB}" > "${CLIENT_DIR}/cudy.pub"

if grep -q "# cudy-tr3000" "${CONF}" || grep -q "${CLIENT_PUB}" "${CONF}"; then
  echo "Пир Cudy уже в ${CONF}"
else
  BACKUP="${CONF}.bak.$(date +%Y%m%d%H%M%S)"
  cp -a "${CONF}" "${BACKUP}"
  echo "Бэкап: ${BACKUP}"
  cat >> "${CONF}" <<EOF

[Peer]
# cudy-tr3000
PublicKey = ${CLIENT_PUB}
AllowedIPs = ${CLIENT_IP}
EOF
  chmod 600 "${CONF}"
fi

echo "== syncconf (без полного restart) =="
STRIP="$(mktemp)"
awg-quick strip "${WG_IF}" > "${STRIP}"
awg syncconf "${WG_IF}" "${STRIP}"
rm -f "${STRIP}"
sleep 2

echo ""
awg show "${WG_IF}"
echo ""
echo "Пиры:"
awg show "${WG_IF}" peers
