#!/bin/sh
# Cudy: если AmneziaWG handshake не жив — обновить host-route и переподнять wg0.
# На VPS отдельно стоит awg-peer-watchdog (серверный сброс пира).
#
#   sh awg-client-watchdog.sh           # один проход
#   sh awg-client-watchdog.sh --install # /usr/sbin + cron
#
set -eu

WG_IF="${WG_IF:-wg0}"
MAX_AGE_SEC="${MAX_AGE_SEC:-120}"
HOTPLUG="${HOTPLUG:-/etc/hotplug.d/iface/99-awg-endpoint}"
INSTALL_BIN="/usr/sbin/awg-client-watchdog"
CRON_LINE="*/2 * * * * ${INSTALL_BIN} >/dev/null 2>&1"

log() { logger -t awg-client-watchdog "$*"; }

if [ "${1:-}" = "--install" ]; then
  SRC="$0"
  case "$SRC" in
    /*) ;;
    *) SRC="$(CDPATH= cd -- "$(dirname "$0")" && pwd)/$(basename "$0")" ;;
  esac
  cp "$SRC" "$INSTALL_BIN"
  chmod 755 "$INSTALL_BIN"
  touch /etc/crontabs/root
  grep -q 'awg-client-watchdog' /etc/crontabs/root 2>/dev/null \
    || echo "$CRON_LINE" >> /etc/crontabs/root
  /etc/init.d/cron enable >/dev/null 2>&1 || true
  /etc/init.d/cron restart >/dev/null 2>&1 || true
  log "installed ${INSTALL_BIN} and crontab"
  exit 0
fi

# Обычный WISP: туннель выключен намеренно, не поднимать.
tm="$(cat /etc/amnezia/traffic-mode 2>/dev/null || echo vpn)"
[ "$tm" = "wisp" ] && exit 0

command -v awg >/dev/null 2>&1 || exit 0
ip link show "${WG_IF}" >/dev/null 2>&1 || exit 0

now="$(date +%s)"
hs="$(awg show "${WG_IF}" latest-handshakes 2>/dev/null | awk 'NR==1 {print $2; exit}')"
hs="${hs:-0}"

if [ "$hs" != "0" ]; then
  age=$((now - hs))
  [ "$age" -lt "$MAX_AGE_SEC" ] && exit 0
else
  age=999999
fi

log "stale handshake age=${age}s — refresh endpoint + bounce ${WG_IF}"
if [ -x "$HOTPLUG" ]; then
  INTERFACE=wwan5 ACTION=ifup sh "$HOTPLUG" 2>/dev/null || true
fi
ifdown "${WG_IF}" 2>/dev/null || true
sleep 1
ifup "${WG_IF}" 2>/dev/null || true
