# Подключение Cudy к VPS

Предполагается: OpenWrt 24.10.5 на Cudy, сервер AmneziaWG на VPS, известны `AWG_SERVER_PUBKEY` и публичный IP VPS.

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
export WG_ENDPOINT=<публичный_IP_VPS>
export AWG_SERVER_PUBKEY='...с VPS...'
sh awg-apply.sh
```

Скрипт настроит `wg0`, kill-switch, DNS через роутер, hotplug host-route. По умолчанию режим трафика — VPN.

Проверка на роутере:

```sh
awg show wg0
ip route get <публичный_IP_VPS>
wget -qO- http://ifconfig.me   # должен быть IP VPS
```

## 6. LuCI

С ПК в LAN / `Travel-VPN`:

```sh
# Смена Wi‑Fi
cd scripts/luci-wisp && ROUTER=192.168.10.1 sh deploy-from-mac.sh

# Статус / настройки AmneziaWG
cd ../luci-awg && ROUTER=192.168.10.1 sh deploy-from-mac.sh

# Режим обычный / VPN (+ обновляет watchdog и mode-aware Смена Wi‑Fi)
cd ../luci-mode && ROUTER=192.168.10.1 sh deploy-from-mac.sh
```

Пароль root для `sshpass` (опционально): `ROUTER_SSH_PASS=...`.

## 7. Client watchdog на Cudy

Уже ставится из `luci-mode/deploy-from-mac.sh`. Вручную:

```sh
scp scripts/router/awg-client-watchdog.sh root@192.168.10.1:/tmp/
ssh root@192.168.10.1 'sh /tmp/awg-client-watchdog.sh --install'
```

В режиме **Обычный** watchdog **не** поднимает `wg0`.

## 8. Проверка с ноутбука

Подключитесь к `Travel-VPN-*` или по кабелю. Шлюз `192.168.10.1`.

```sh
cd scripts/router
EXPECTED_IP=<публичный_IP_VPS> ROUTER=192.168.10.1 sh verify-awg.sh
sh verify-awg.sh --long   # выдержка 3+ мин и kill-switch
```

## Типичные проблемы

| Симптом | Что проверить |
|---------|----------------|
| Handshake есть, IP не VPS | host-route: `ip route get <VPS_IP>` → через `phy*-sta*`, не `wg0` |
| Нет handshake | UDP 443 до VPS с uplink; `awg-params` совпадают |
| kmod не грузится | vermagic `.ko` и `uname -r` |
| Клиенты без интернета при живом wg0 | форвардинг `lan→wg`, DNS `192.168.10.1` |
| WISP жив, 0 B received | [08-tunnel-recovery.md](08-tunnel-recovery.md) |

Смена uplink: [05-switch-wifi.md](05-switch-wifi.md). Режимы: [06-traffic-mode.md](06-traffic-mode.md).
