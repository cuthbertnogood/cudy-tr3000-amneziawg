#!/bin/sh
# Установка страницы Network → AmneziaWG.
set -eu

ROOT="${1:-$(CDPATH= cd -- "$(dirname "$0")" && pwd)}"

mkdir -p /usr/libexec
cp "${ROOT}/awg-config.sh" /usr/libexec/awg-config.sh
chmod 755 /usr/libexec/awg-config.sh

mkdir -p /www/luci-static/resources/view/amneziawg
cp "${ROOT}/settings.js" /www/luci-static/resources/view/amneziawg/settings.js
chmod 644 /www/luci-static/resources/view/amneziawg/settings.js
cp "${ROOT}/status.js" /www/luci-static/resources/view/amneziawg/status.js
chmod 644 /www/luci-static/resources/view/amneziawg/status.js

mkdir -p /usr/share/luci/menu.d
cp "${ROOT}/luci-app-amneziawg-menu.json" /usr/share/luci/menu.d/luci-app-amneziawg.json
chmod 644 /usr/share/luci/menu.d/luci-app-amneziawg.json

mkdir -p /usr/share/rpcd/acl.d
cp "${ROOT}/luci-app-amneziawg-acl.json" /usr/share/rpcd/acl.d/luci-app-amneziawg.json
chmod 644 /usr/share/rpcd/acl.d/luci-app-amneziawg.json

# endpoint-файл из текущего UCI, если ещё нет
mkdir -p /etc/amnezia
if [ ! -f /etc/amnezia/endpoint ]; then
	ep=$(uci -q get network.wgvps.endpoint_host 2>/dev/null || true)
	[ -n "$ep" ] || ep=$(uci -q get network.wgserver.endpoint_host 2>/dev/null || true)
	[ -n "$ep" ] && printf '%s\n' "$ep" > /etc/amnezia/endpoint
fi

rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache 2>/dev/null || true
mkdir -p /tmp/luci-modulecache

/etc/init.d/rpcd reload 2>/dev/null || true
/etc/init.d/uhttpd reload 2>/dev/null || /etc/init.d/uhttpd restart

echo "OK: Network → Статус VPN / AmneziaWG"
echo "Статус:   http://192.168.10.1/cgi-bin/luci/admin/network/amneziawg-status"
echo "Настройки: http://192.168.10.1/cgi-bin/luci/admin/network/amneziawg"
