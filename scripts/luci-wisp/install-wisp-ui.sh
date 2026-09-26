#!/bin/sh
# Установка страницы «Смена Wi‑Fi» (современный LuCI / ucode).
set -eu

ROOT="${1:-$(CDPATH= cd -- "$(dirname "$0")" && pwd)}"

mkdir -p /usr/libexec
cp "${ROOT}/wisp-switch.sh" /usr/libexec/wisp-switch.sh
chmod 755 /usr/libexec/wisp-switch.sh
cp "${ROOT}/wisp-scan-worker.sh" /usr/libexec/wisp-scan-worker.sh
chmod 755 /usr/libexec/wisp-scan-worker.sh

mkdir -p /www/luci-static/resources/view/wisp
cp "${ROOT}/switch.js" /www/luci-static/resources/view/wisp/switch.js
chmod 644 /www/luci-static/resources/view/wisp/switch.js

mkdir -p /usr/share/luci/menu.d
cp "${ROOT}/luci-app-wisp-menu.json" /usr/share/luci/menu.d/luci-app-wisp.json
chmod 644 /usr/share/luci/menu.d/luci-app-wisp.json

mkdir -p /usr/share/rpcd/acl.d
cp "${ROOT}/luci-app-wisp-acl.json" /usr/share/rpcd/acl.d/luci-app-wisp.json
chmod 644 /usr/share/rpcd/acl.d/luci-app-wisp.json

# старый lua-вариант убрать, если был
rm -f /usr/lib/lua/luci/controller/wisp.lua
rm -rf /usr/lib/lua/luci/view/wisp

rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache 2>/dev/null || true
mkdir -p /tmp/luci-modulecache

/etc/init.d/rpcd reload 2>/dev/null || true
/etc/init.d/uhttpd reload 2>/dev/null || /etc/init.d/uhttpd restart

echo "OK: Network → Смена Wi‑Fi"
echo "URL: http://192.168.10.1/cgi-bin/luci/admin/network/wisp"
