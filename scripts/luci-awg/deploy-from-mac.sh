#!/usr/bin/env bash
# С ПК в LAN Cudy: страницы «Статус VPN» и «AmneziaWG».
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
ROUTER="${ROUTER:-192.168.10.1}"
SSH_PASS="${ROUTER_SSH_PASS:-}"
SSH=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8)
HOTPLUG_SRC="${ROOT}/../router/wwan-endpoint-route.sh"

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

run_ssh "root@${ROUTER}" 'mkdir -p /tmp/awg-ui'
run_scp \
  "${ROOT}/awg-config.sh" \
  "${ROOT}/settings.js" \
  "${ROOT}/status.js" \
  "${ROOT}/luci-app-amneziawg-menu.json" \
  "${ROOT}/luci-app-amneziawg-acl.json" \
  "${ROOT}/install-awg-ui.sh" \
  "root@${ROUTER}:/tmp/awg-ui/"

if [[ -f "$HOTPLUG_SRC" ]]; then
  run_scp "$HOTPLUG_SRC" "root@${ROUTER}:/tmp/wwan-endpoint-route.sh"
  run_ssh "root@${ROUTER}" 'sh /tmp/wwan-endpoint-route.sh --install'
fi

run_ssh "root@${ROUTER}" 'sh /tmp/awg-ui/install-awg-ui.sh'
echo "Статус:    http://${ROUTER}/cgi-bin/luci/admin/network/amneziawg-status"
echo "Настройки: http://${ROUTER}/cgi-bin/luci/admin/network/amneziawg"
