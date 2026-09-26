#!/bin/sh
# Host-route до AmneziaWG endpoint через активный WISP (wwan5 / wwan24).
#
# На роутере: /etc/hotplug.d/iface/99-awg-endpoint
# Установка:  WG_ENDPOINT=VPS_IP sh wwan-endpoint-route.sh --install
#
WG_IF="${WG_IF:-wg0}"
HOTPLUG_DST="/etc/hotplug.d/iface/99-awg-endpoint"

endpoint_from_uci() {
  uci -q get network.endpoint_host.target 2>/dev/null \
    || uci -q get network.wgvps.endpoint_host 2>/dev/null \
    || true
}

ENDPOINT="${WG_ENDPOINT:-}"
[ -z "${ENDPOINT}" ] && ENDPOINT="$(endpoint_from_uci)"

if [ -z "${ENDPOINT}" ] && [ "${1:-}" = "--install" ]; then
  echo "Задайте WG_ENDPOINT=<публичный IP VPS>" >&2
  exit 1
fi
[ -z "${ENDPOINT}" ] && exit 0

if [ "${1:-}" = "--install" ]; then
  SRC="$0"
  case "$SRC" in
    /*) ;;
    *) SRC="$(CDPATH= cd -- "$(dirname "$0")" && pwd)/$(basename "$0")" ;;
  esac
  mkdir -p "$(dirname "${HOTPLUG_DST}")"
  cp "${SRC}" "${HOTPLUG_DST}"
  chmod 755 "${HOTPLUG_DST}"
  echo "installed ${HOTPLUG_DST}"
  INTERFACE="${INTERFACE:-wwan5}" ACTION="${ACTION:-ifup}" sh "${HOTPLUG_DST}" || true
  exit 0
fi

case "${ACTION:-}" in
  ifup|ifupdate) ;;
  *) exit 0 ;;
esac

case "${INTERFACE:-}" in
  wwan5|wwan24) ;;
  *) exit 0 ;;
esac

best_metric=999999
best_gw=""
best_dev=""
best_if=""

for ifc in wwan5 wwan24; do
  st=$(ifstatus "${ifc}" 2>/dev/null) || continue
  echo "${st}" | grep -q '"up": true' || continue
  dev=$(echo "${st}" | jsonfilter -e '@.l3_device' 2>/dev/null)
  metric=$(echo "${st}" | jsonfilter -e '@.metric' 2>/dev/null)
  gw=$(echo "${st}" | jsonfilter -e '@["inactive"]["route"][0].nexthop' 2>/dev/null)
  [ -n "${gw}" ] || gw=$(echo "${st}" | jsonfilter -e '@.route[0].nexthop' 2>/dev/null)
  [ -n "${dev}" ] && [ -n "${gw}" ] || continue
  case "${metric}" in
    ''|*[!0-9]*) metric=$(uci -q get "network.${ifc}.metric" 2>/dev/null || echo 100) ;;
  esac
  case "${metric}" in
    ''|*[!0-9]*) metric=100 ;;
  esac
  if [ "${metric}" -lt "${best_metric}" ]; then
    best_metric="${metric}"
    best_gw="${gw}"
    best_dev="${dev}"
    best_if="${ifc}"
  fi
done

[ -n "${best_gw}" ] && [ -n "${best_dev}" ] || exit 0

ip -4 route show "${ENDPOINT}" 2>/dev/null | while read -r line; do
  # shellcheck disable=SC2086
  ip route del $line 2>/dev/null || true
done
ip route replace "${ENDPOINT}/32" via "${best_gw}" dev "${best_dev}"

uci -q delete network.endpoint_host 2>/dev/null || true
while uci -q delete network.endpoint_host 2>/dev/null; do :; done
uci set network.endpoint_host=route
uci set network.endpoint_host.interface="${best_if}"
uci set network.endpoint_host.target="${ENDPOINT}"
uci set network.endpoint_host.netmask='255.255.255.255'
uci set network.endpoint_host.gateway="${best_gw}"
uci commit network

need_up=0
if ! ip link show "${WG_IF}" >/dev/null 2>&1; then
  need_up=1
elif ! ip -4 addr show "${WG_IF}" 2>/dev/null | grep -q 'inet '; then
  need_up=1
else
  hs=$(awg show "${WG_IF}" latest-handshakes 2>/dev/null | awk 'NR==1 {print $2; exit}')
  hs=${hs:-0}
  [ "${hs}" = "0" ] && need_up=1
fi

if [ "${need_up}" = "1" ]; then
  ifup "${WG_IF}" 2>/dev/null || true
fi

logger -t awg-endpoint "endpoint ${ENDPOINT}/32 via ${best_gw} dev ${best_dev} (${best_if} metric ${best_metric})"
