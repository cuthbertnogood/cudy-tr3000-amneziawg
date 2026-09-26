# Подключение Cudy к VPS

Предполагается: OpenWrt 24.10.5 на Cudy, сервер AmneziaWG на VPS, известны `AWG_SERVER_PUBKEY` и `VPS_IP`.

## 1. Скопировать файлы на роутер

С ПК в LAN Cudy:

```sh
ROUTER=192.168.10.1
scp -r scripts/router/* root@${ROUTER}:/tmp/router/
scp scripts/router/awg-params.env root@${ROUTER}:/tmp/router/
# awg-params.env — копия с VPS (не example)
```

## 2. Модуль ядра amneziawg

На ПК с Docker:

```sh
cd scripts/router
sh build-kmod-cudy-docker.sh
KVER=$(ssh root@192.168.10.1 uname -r)
scp out/amneziawg-cudy.ko root@192.168.10.1:/lib/modules/${KVER}/amneziawg.ko
```

На роутере:

```sh
depmod -a
insmod /lib/modules/$(uname -r)/amneziawg.ko
echo amneziawg > /etc/modules.d/99-amneziawg
```

Установите `awg` (CLI): `opkg update && opkg install amneziawg-tools ip-full` или `.ipk` из SDK.

## 3. WISP + точки доступа

Задайте SSID и пароли **вашего** uplink (два диапазона, если есть) и пароль AP для клиентов:

```sh
cd /tmp/router
WISP5_SSID='UPLINK_5' \
WISP24_SSID='UPLINK_24' \
WISP_KEY='пароль_uplink' \
AP_KEY='пароль_Travel-VPN' \
sh setup-wisp.sh
```

Проверьте, что `wwan5` или `wwan24` получили IP (`ifstatus wwan5`).

## 4. Ключ клиента → сервер (если ещё не сделано)

```sh
sh awg-apply.sh
# скопируйте CLIENT_PUB на VPS → awg-server.sh
```

## 5. Клиент AmneziaWG (второй проход)

```sh
export WG_ENDPOINT=VPS_IP
export AWG_SERVER_PUBKEY='...с VPS...'
sh awg-apply.sh
```

Скрипт настроит `wg0`, kill-switch, DNS через роутер, hotplug host-route.

Проверка на роутере:

```sh
awg show wg0
ip route get VPS_IP
wget -qO- http://ifconfig.me   # должен быть VPS_IP
```

## 6. LuCI «Смена Wi‑Fi»

С ПК:

```sh
cd scripts/luci-wisp
ROUTER=192.168.10.1 ROUTER_SSH_PASS='...' sh deploy-from-mac.sh
# или ssh + scp вручную, затем на роутере: sh install-wisp-ui.sh
```

## 7. Проверка с ноутбука

Подключитесь к `Travel-VPN-*` или по кабелю. Шлюз `192.168.10.1`.

```sh
cd scripts/router
EXPECTED_IP=VPS_IP ROUTER=192.168.10.1 sh verify-awg.sh
sh verify-awg.sh --long   # выдержка 3+ мин и kill-switch
```

## Типичные проблемы

| Симптом | Что проверить |
|---------|----------------|
| Handshake есть, IP не VPS | host-route: `ip route get VPS_IP` → через `phy*-sta*`, не `wg0` |
| Нет handshake | UDP 443 до VPS с uplink; `awg-params` совпадают |
| kmod не грузится | vermagic `.ko` и `uname -r` |
| Клиенты без интернета при живом wg0 | форвардинг `lan→wg`, DNS `192.168.10.1` |

Смена uplink без SSH: [05-switch-wifi.md](05-switch-wifi.md).
