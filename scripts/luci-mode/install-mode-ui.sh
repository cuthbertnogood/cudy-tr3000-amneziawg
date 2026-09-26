#!/bin/sh
# Страница «Режим интернета» + скрипт переключения + init на boot.
set -eu

ROOT="${1:-$(CDPATH= cd -- "$(dirname "$0")" && pwd)}"

mkdir -p /usr/libexec /etc/amnezia /etc/init.d
cp "${ROOT}/awg-mode.sh" /usr/libexec/awg-mode.sh
chmod 755 /usr/libexec/awg-mode.sh

cp "${ROOT}/awg-traffic-mode.init" /etc/init.d/awg-traffic-mode
chmod 755 /etc/init.d/awg-traffic-mode
/etc/init.d/awg-traffic-mode enable

if [ ! -f /etc/amnezia/traffic-mode ]; then
	printf '%s\n' vpn > /etc/amnezia/traffic-mode
fi

mkdir -p /www/luci-static/resources/view/traffic-mode
cp "${ROOT}/mode.js" /www/luci-static/resources/view/traffic-mode/mode.js
cp "${ROOT}/wisp.svg" /www/luci-static/resources/view/traffic-mode/wisp.svg
cp "${ROOT}/vpn.svg" /www/luci-static/resources/view/traffic-mode/vpn.svg
chmod 644 /www/luci-static/resources/view/traffic-mode/mode.js \
	/www/luci-static/resources/view/traffic-mode/wisp.svg \
	/www/luci-static/resources/view/traffic-mode/vpn.svg

mkdir -p /usr/share/luci/menu.d /usr/share/rpcd/acl.d
cp "${ROOT}/luci-app-traffic-mode-menu.json" /usr/share/luci/menu.d/luci-app-traffic-mode.json
cp "${ROOT}/luci-app-traffic-mode-acl.json" /usr/share/rpcd/acl.d/luci-app-traffic-mode.json
chmod 644 /usr/share/luci/menu.d/luci-app-traffic-mode.json \
	/usr/share/rpcd/acl.d/luci-app-traffic-mode.json

rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache 2>/dev/null || true
mkdir -p /tmp/luci-modulecache

/etc/init.d/rpcd reload 2>/dev/null || true
/etc/init.d/uhttpd reload 2>/dev/null || /etc/init.d/uhttpd restart

echo "OK: Network → Режим интернета"
echo "URL: http://192.168.10.1/cgi-bin/luci/admin/network/traffic-mode"
