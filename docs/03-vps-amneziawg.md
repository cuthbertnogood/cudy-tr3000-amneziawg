# AmneziaWG на VPS (Ubuntu / Debian)

VPS с публичным IPv4, root по SSH. Порт **UDP 443** (или свой `WG_PORT`) должен быть открыт в firewall панели хостера.

## 1. Подготовка

```sh
ssh root@VPS_IP
apt-get update && apt-get install -y curl ca-certificates
```

Узнайте имя внешнего интерфейса (часто `eth0` или `ens3`):

```sh
ip -4 route show default
# запомните dev=...
export EXT_IF=eth0   # подставьте своё
```

## 2. Параметры маскировки

На VPS скопируйте из репозитория:

```sh
mkdir -p /root/cudy-awg
# scp scripts/vps/* root@VPS_IP:/root/cudy-awg/
cd /root/cudy-awg
cp awg-params.env.example awg-params.env
# при необходимости отредактируйте Jc/Jmin/... — те же значения потом на Cudy
```

## 3. Публичный ключ Cudy (CLIENT_PUB)

На **роутере** (после прошивки OpenWrt, до полной настройки VPN):

1. Скопируйте `scripts/router/` на Cudy (scp в `/tmp/`).
2. Положите `awg-params.env` (как на VPS).
3. Установите kmod и `awg` (см. [04-connect-cudy.md](04-connect-cudy.md)) или временно только tools для генерации ключа.
4. Запустите **первый проход** клиента:

```sh
sh /tmp/router/awg-apply.sh
# выведет CLIENT_PUB — скопируйте на VPS
```

Либо на VPS сгенерируйте пару на роутере позже; сервер без `CLIENT_PUB` не стартует.

## 4. Установка сервера

На VPS:

```sh
cd /root/cudy-awg
export EXT_IF=eth0
export WG_PORT=443
export CLIENT_IP=10.9.0.2/32

CLIENT_PUB='...ключ с роутера...' sh awg-server.sh
```

Скрипт:

- ставит **amneziawg** из PPA `amnezia/ppa`;
- отключает обычный `wg-quick@wg0`, если был;
- создаёт `/etc/amnezia/amneziawg/wg0.conf` с одним пиром Cudy;
- включает NAT для `10.9.0.0/24` на `EXT_IF`;
- запускает `awg-quick@wg0`.

В выводе сохраните **публичный ключ сервера** — он понадобится на Cudy как `AWG_SERVER_PUBKEY`.

Проверка:

```sh
awg show wg0
ss -ulnp | grep ':443'
```

## 5. Firewall хостера

В панели VPS откройте **входящий UDP** на `WG_PORT` (443). UFW на сервере скрипт подправит, если UFW активен.

## 6. Добавить второй пир позже (опционально)

Если сервер уже работает и нужен ещё клиент с другим IP:

```sh
CLIENT_PUB='...' CLIENT_IP=10.9.0.3/32 sh awg-add-peer.sh
```

Для схемы «только Cudy» достаточно одного пира из `awg-server.sh`.

## 7. Что передать на Cudy

| Переменная | Откуда |
|------------|--------|
| `WG_ENDPOINT` | публичный `VPS_IP` |
| `WG_PORT` | 443 |
| `AWG_SERVER_PUBKEY` | вывод `awg-server.sh` |
| `awg-params.env` | тот же файл, что на VPS |

Дальше: [04-connect-cudy.md](04-connect-cudy.md).
