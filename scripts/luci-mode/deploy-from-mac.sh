#!/usr/bin/env bash
# С ПК в LAN Cudy: страница «Режим интернета» + mode-aware WISP / watchdog / hotplug.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "${ROOT}/../.." && pwd)"
ROUTER="${ROUTER:-192.168.10.1}"
SSH_PASS="${ROUTER_SSH_PASS:-}"
SSH=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8)

run_ssh() {
  if [ -n "${SSH_PASS}" ] && command -v sshpass >/dev/null 2>&1; then
    sshpass -p "${SSH_PASS}" ssh "${SSH[@]}" "$@"
  else
    ssh "${SSH[@]}" "$@"
  fi
}

run_scp() {
  if [ -n "${SSH_PASS}" ] && command -v sshpass >/dev/null 2>&1; then
    sshpass -p "${SSH_PASS}" scp -O "${SSH[@]}" "$@"
  else
    scp -O "${SSH[@]}" "$@"
  fi
}

run_ssh "root@${ROUTER}" 'mkdir -p /tmp/mode-ui /tmp/wisp-ui'
run_scp \
  "${ROOT}/awg-mode.sh" \
  "${ROOT}/awg-traffic-mode.init" \
  "${ROOT}/mode.js" \
  "${ROOT}/wisp.svg" \
  "${ROOT}/vpn.svg" \
  "${ROOT}/luci-app-traffic-mode-menu.json" \
  "${ROOT}/luci-app-traffic-mode-acl.json" \
  "${ROOT}/install-mode-ui.sh" \
  "root@${ROUTER}:/tmp/mode-ui/"

run_scp \
  "${REPO}/scripts/luci-wisp/wisp-switch.sh" \
  "${REPO}/scripts/luci-wisp/switch.js" \
  "root@${ROUTER}:/tmp/wisp-ui/"

run_scp \
  "${REPO}/scripts/router/wwan-endpoint-route.sh" \
  "${REPO}/scripts/router/awg-client-watchdog.sh" \
  "root@${ROUTER}:/tmp/"

run_ssh "root@${ROUTER}" '
  sh /tmp/mode-ui/install-mode-ui.sh
  cp /tmp/wisp-ui/wisp-switch.sh /usr/libexec/wisp-switch.sh
  cp /tmp/wisp-ui/switch.js /www/luci-static/resources/view/wisp/switch.js
  chmod 755 /usr/libexec/wisp-switch.sh
  chmod 644 /www/luci-static/resources/view/wisp/switch.js
  sh /tmp/wwan-endpoint-route.sh --install
  sh /tmp/awg-client-watchdog.sh --install
  rm -f /tmp/luci-indexcache
'
echo "Режим:  http://${ROUTER}/cgi-bin/luci/admin/network/traffic-mode"
echo "Wi‑Fi:  http://${ROUTER}/cgi-bin/luci/admin/network/wisp"
