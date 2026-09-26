#!/usr/bin/env bash
# С ПК в LAN Cudy: страница «Смена Wi‑Fi».
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
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

run_ssh "root@${ROUTER}" 'mkdir -p /tmp/wisp-ui'
run_scp \
  "${ROOT}/wisp-switch.sh" \
  "${ROOT}/wisp-scan-worker.sh" \
  "${ROOT}/switch.js" \
  "${ROOT}/luci-app-wisp-menu.json" \
  "${ROOT}/luci-app-wisp-acl.json" \
  "${ROOT}/install-wisp-ui.sh" \
  "root@${ROUTER}:/tmp/wisp-ui/"
run_ssh "root@${ROUTER}" 'sh /tmp/wisp-ui/install-wisp-ui.sh'
echo "Откройте: http://${ROUTER}/cgi-bin/luci/admin/network/wisp"
