# Обрыв туннеля и watchdog

## Симптом

Телефон в `Travel-VPN` без интернета. Админка `http://192.168.10.1` открывается. WISP к чужому Wi‑Fi жив (сигнал STA, IP на `phy*-sta0`), пинг до публичного IP VPS с Cudy проходит, а `awg show` — **0 B received**, пинг `10.9.0.1` не идёт.

В режиме **VPN** это **kill-switch**: без handshake наружу с LAN пускать нельзя. Сначала убедитесь, что `/etc/amnezia/traffic-mode` = `vpn` (не перепутали с обычным режимом).

## Типичная причина

Не WISP и не ключи. На VPS у пира Cudy **зависла сессия AmneziaWG** (старый endpoint, handshake сутки). UDP с Cudy доходит до порта, а handshake **игнорируется**.  
`ifdown`/`ifup wg0` на роутере часто **не лечит**. Помогает сброс пира на сервере: `remove` + снова `allowed-ips`.

## Автовосстановление

| Где | Скрипт | Крон | Действие |
|-----|--------|------|----------|
| **VPS** | `scripts/vps/awg-peer-watchdog.sh` → `/usr/local/sbin/…` | `/etc/cron.d/awg-peer-watchdog` каждые **2 мин** | handshake старше ~5 мин → `awg set peer remove` + `allowed-ips`. Cooldown 10 мин на офлайн-пир |
| **Cudy** | `scripts/router/awg-client-watchdog.sh` → `/usr/sbin/…` | crontab root каждые **2 мин** | handshake старше ~2 мин → hotplug host-route + bounce `wg0`. В режиме `wisp` — выход без действий |

Установка:

```bash
# на VPS
sudo sh scripts/vps/awg-peer-watchdog.sh --install

# на Cudy (уже входит в luci-mode/deploy-from-mac.sh)
scp scripts/router/awg-client-watchdog.sh root@192.168.10.1:/tmp/
ssh root@192.168.10.1 'sh /tmp/awg-client-watchdog.sh --install'
```

## Ручной сброс пира на VPS

Подставьте **публичный ключ клиента** Cudy (со страницы AmneziaWG или `awg show`):

```bash
sudo awg set wg0 peer <CLIENT_PUBKEY> remove
sudo awg set wg0 peer <CLIENT_PUBKEY> allowed-ips 10.9.0.2/32
```

Затем на Cudy: `ifdown wg0; ifup wg0` (или подождать client-watchdog).

## Диагностика на роутере

```sh
cat /etc/amnezia/traffic-mode
awg show wg0
ip -4 route get "$(cat /etc/amnezia/endpoint)"
ping -c 2 10.9.0.1
wget -qO- http://ifconfig.me/ip; echo
```

Админка LuCI доступна из `Travel-VPN` без внешнего интернета: `http://192.168.10.1`.

Связанные доки: [04-connect-cudy.md](04-connect-cudy.md), [06-traffic-mode.md](06-traffic-mode.md), [07-amneziawg-ui.md](07-amneziawg-ui.md).
