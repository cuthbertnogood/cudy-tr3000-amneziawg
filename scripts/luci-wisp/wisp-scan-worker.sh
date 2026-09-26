#!/bin/sh
# Worker: полный скан Wi‑Fi вне HTTP/ubus-запроса.
SCAN_OUT="${SCAN_OUT:-/tmp/wisp-scan.out}"
SCAN_STATE="${SCAN_STATE:-/tmp/wisp-scan.state}"
SCAN_ERR="${SCAN_ERR:-/tmp/wisp-scan.err}"

exec >/dev/null 2>"${SCAN_ERR}"
if /usr/libexec/wisp-switch.sh scan > "${SCAN_OUT}.tmp"; then
	mv "${SCAN_OUT}.tmp" "${SCAN_OUT}"
	echo done > "${SCAN_STATE}"
else
	rm -f "${SCAN_OUT}.tmp"
	echo error > "${SCAN_STATE}"
fi
