#!/bin/sh
# VPS: сброс пиров AmneziaWG с зависшим handshake.
#
# Если UDP до порта доходит, а handshake на одном пире завис — ifdown/ifup
# на клиенте часто не помогает; нужен remove + снова allowed-ips на сервере.
#
#   sudo sh awg-peer-watchdog.sh           # один проход
#   sudo sh awg-peer-watchdog.sh --install # /usr/local/sbin + cron.d
#
set -eu

WG_IF="${WG_IF:-wg0}"
# keepalive 25s → живой пир обновляет handshake обычно < 2 мин
MAX_AGE_SEC="${MAX_AGE_SEC:-300}"
# не долбить один и тот же оффлайн-пир чаще
COOLDOWN_SEC="${COOLDOWN_SEC:-600}"
STATE_DIR="${STATE_DIR:-/run/awg-peer-watchdog}"
INSTALL_BIN="/usr/local/sbin/awg-peer-watchdog.sh"
CRON_FILE="/etc/cron.d/awg-peer-watchdog"

log() { logger -t awg-peer-watchdog "$*"; echo "$*"; }

if [ "${1:-}" = "--install" ]; then
  SRC="$0"
  case "$SRC" in
    /*) ;;
    *) SRC="$(CDPATH= cd -- "$(dirname "$0")" && pwd)/$(basename "$0")" ;;
  esac
  install -m 755 "$SRC" "$INSTALL_BIN"
  cat >"$CRON_FILE" <<EOF
# AmneziaWG: reset peers with stale handshake
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
*/2 * * * * root ${INSTALL_BIN} >/dev/null 2>&1
EOF
  chmod 644 "$CRON_FILE"
  log "installed ${INSTALL_BIN} and ${CRON_FILE}"
  "$INSTALL_BIN" || true
  exit 0
fi

command -v awg >/dev/null 2>&1 || { echo "awg not found" >&2; exit 1; }
ip link show "${WG_IF}" >/dev/null 2>&1 || exit 0

mkdir -p "${STATE_DIR}"
chmod 700 "${STATE_DIR}"
now="$(date +%s)"

# pubkey<TAB>unix_ts (0 = never)
awg show "${WG_IF}" latest-handshakes | while IFS=$(printf '\t') read -r pub hs; do
  [ -n "${pub:-}" ] || continue
  hs="${hs:-0}"
  safe="$(echo "$pub" | tr '/+' '__')"
  stamp="${STATE_DIR}/${safe}"

  if [ "$hs" != "0" ]; then
    age=$((now - hs))
    if [ "$age" -lt "$MAX_AGE_SEC" ]; then
      rm -f "$stamp"
      continue
    fi
  else
    age=999999
  fi

  if [ -f "$stamp" ]; then
    last="$(cat "$stamp" 2>/dev/null || echo 0)"
    if [ $((now - last)) -lt "$COOLDOWN_SEC" ]; then
      continue
    fi
  fi

  # allowed-ips: "pubkey\tip1 ip2"
  ips="$(awg show "${WG_IF}" allowed-ips | awk -v p="$pub" '
    $1 == p {
      $1 = ""
      sub(/^ /, "")
      gsub(/ /, ",")
      print
      exit
    }')"
  if [ -z "$ips" ]; then
    log "skip ${pub}: no allowed-ips"
    continue
  fi

  log "reset peer ${pub} (handshake age ${age}s > ${MAX_AGE_SEC}s) allowed-ips=${ips}"
  awg set "${WG_IF}" peer "$pub" remove
  # shellcheck disable=SC2086
  awg set "${WG_IF}" peer "$pub" allowed-ips "$ips"
  echo "$now" >"$stamp"
done
