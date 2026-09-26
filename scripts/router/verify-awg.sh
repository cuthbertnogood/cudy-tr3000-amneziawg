#!/bin/sh
# Проверка AmneziaWG Cudy → VPS (Mac/ПК в LAN или Wi‑Fi Travel-VPN).
#
#   EXPECTED_IP=VPS_IP ROUTER=192.168.10.1 sh verify-awg.sh
#   sh verify-awg.sh --long
#
set -eu

ROUTER="${ROUTER:-192.168.10.1}"
EXPECTED_IP="${EXPECTED_IP:-}"
LONG="${LONG:-0}"
SSH_PASS="${ROUTER_SSH_PASS:-}"

for arg in "$@"; do
  case "$arg" in
    --long) LONG=1 ;;
  esac
done

if [ -z "${EXPECTED_IP}" ]; then
  echo "Задайте EXPECTED_IP=<публичный IP VPS>" >&2
  exit 1
fi

ssh_router() {
  if [ -n "${SSH_PASS}" ] && command -v sshpass >/dev/null 2>&1; then
    sshpass -p "${SSH_PASS}" ssh -o ConnectTimeout=8 -o StrictHostKeyChecking=no "root@${ROUTER}" "$@"
  else
    ssh -o ConnectTimeout=8 -o StrictHostKeyChecking=no "root@${ROUTER}" "$@"
  fi
}

check_handshake() {
  echo ""
  echo "== handshake / ping (роутер ${ROUTER}) =="
  ssh_router 'HS=$(awg show wg0 latest-handshakes 2>/dev/null | awk "{print \$2}"); NOW=$(date +%s); if [ -n "$HS" ] && [ "$HS" != "0" ]; then AGE=$((NOW-HS)); echo "handshake age: ${AGE}s"; else echo "handshake: none"; fi; awg show wg0 2>/dev/null | head -20; ping -c 3 -W 2 10.9.0.1; ping -c 3 -W 2 1.1.1.1'
}

fail=0
ok() { echo "OK: $*"; }
warn() { echo "WARN: $*"; }
bad() { echo "FAIL: $*"; fail=1; }

echo "== шлюз по умолчанию =="
GW="$(route -n get default 2>/dev/null | awk '/gateway/ {print $2}' || true)"
echo "default gateway → ${GW:-нет}"
if [ "$GW" = "$ROUTER" ]; then
  ok "маршрут через Cudy"
else
  warn "шлюз не ${ROUTER} — подключите ПК к LAN/Wi‑Fi Travel-VPN Cudy"
fi

echo ""
echo "== внешний IP =="
IP="$(curl -sS -4 --max-time 20 https://ifconfig.me || echo FAIL)"
echo "ifconfig.me → ${IP}"
if [ "$IP" = "$EXPECTED_IP" ]; then
  ok "egress через VPS"
else
  bad "ожидался ${EXPECTED_IP}, получен ${IP}"
fi

echo ""
echo "== DNS =="
RESOLVER="$(scutil --dns 2>/dev/null | awk '/nameserver\[0\]/ {print $3; exit}' || true)"
echo "первый nameserver → ${RESOLVER:-неизвестно}"
if [ "$RESOLVER" = "192.168.10.1" ]; then
  ok "DNS через Cudy"
else
  warn "DNS не 192.168.10.1"
fi
if command -v dig >/dev/null 2>&1; then
  DIG="$(dig @"${ROUTER}" whoami.akamai.net +short +time=3 2>/dev/null | head -1 || true)"
  echo "dig @${ROUTER} whoami.akamai.net → ${DIG:-FAIL}"
fi

check_handshake

if [ "$LONG" = "1" ]; then
  echo ""
  echo "== выдержка 90 с =="
  sleep 90
  check_handshake
  echo ""
  echo "== ещё 90 с (всего ~3 мин) =="
  sleep 90
  check_handshake
fi

echo ""
echo "== kill-switch (ifdown wg0 на роутере) =="
ssh_router 'ifdown wg0; sleep 2' || true
LEAK="$(curl -sS -4 --max-time 8 https://1.1.1.1 -o /dev/null -w '%{http_code}' 2>/dev/null || echo 000)"
echo "curl 1.1.1.1 при wg0 down → HTTP ${LEAK}"
if [ "$LEAK" = "000" ] || [ "$LEAK" = "000000" ]; then
  ok "утечки нет"
else
  bad "трафик прошёл при выключенном туннеле (HTTP ${LEAK})"
fi
ssh_router 'ifup wg0; sleep 5' || true
IP2="$(curl -sS -4 --max-time 20 https://ifconfig.me || echo FAIL)"
echo "ifconfig.me после ifup → ${IP2}"
[ "$IP2" = "$EXPECTED_IP" ] && ok "туннель восстановлен" || bad "egress после ifup: ${IP2}"

if [ "$fail" -eq 0 ]; then
  echo ""
  echo "=== verify-awg (Cudy): PASS ==="
  exit 0
fi
echo ""
echo "=== verify-awg (Cudy): FAIL ==="
exit 1
