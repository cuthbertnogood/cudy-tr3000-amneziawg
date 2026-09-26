# Обзор: travel VPN-шлюз на Cudy TR3000

## Задача

У вас есть:

- роутер **Cudy TR3000** с OpenWrt;
- **VPS** с публичным IP.

Нужно: подключить Cudy к **любому** доступному Wi‑Fi (отель, кафе, соседская сеть), а телефоны и ноутбуки — к Wi‑Fi Cudy. В режиме **VPN** весь трафик идёт только через AmneziaWG на VPS (kill-switch). В режиме **Обычный** — напрямую через чужой Wi‑Fi, без туннеля.

## Что не входит в этот репозиторий

- Готовый `.bin` с уже вшитым AmneziaWG — только официальный OpenWrt + отдельный модуль ядра.
- Хостинг VPS и оплата — вы выбираете провайдера сами.
- Приложение AmneziaVPN на телефоне — здесь схема **роутер-шлюз**, не клиент на каждом устройстве.

## Функции

### Dual WISP (два uplink)

Cudy одновременно может быть клиентом Wi‑Fi на **5 ГГц** (`wwan5`, metric 10) и **2,4 ГГц** (`wwan24`, metric 20). Это два пути до чужой сети (часто 5 и 2,4 ГГц одного роутера).

- **Failover:** если 5 ГГц пропал, hotplug переносит host-route до VPS на 2,4 ГГц.
- **Не bonding:** скорости не складываются; в режиме VPN весь пользовательский трафик идёт в один `wg0`.

### Точки доступа Travel-VPN

Отдельные SSID (по умолчанию `Travel-VPN-2.4G` / `Travel-VPN-5G`) — сюда подключаются ваши устройства. Их SSID при смене uplink не меняются. Кабель в LAN-порт Cudy — в той же зоне `lan`, те же режимы трафика.

### Kill-switch (только режим VPN)

Форвардинг только `lan → wg`. Нет `lan → wan` через WISP. WISP используется для пакетов до endpoint VPS и для самого туннеля, не как «обход» для клиентов LAN. В режиме **Обычный** kill-switch выключен: есть `lan → wan`, `wg0` down.

### Host-route до VPS

Пакеты UDP к `VPS_IP` идут через активный WISP, а не внутрь туннеля (иначе handshake «есть», egress — нет).

### Страницы LuCI

| Страница | Меню | Назначение |
|----------|-------|------------|
| Смена Wi‑Fi | Network → Смена Wi‑Fi | скан / пароль / uplink band |
| Режим интернета | Network → Режим интернета | обычный WISP ↔ VPN |
| Статус VPN | Network → Статус VPN | handshake, трафик, сырой `awg show` |
| AmneziaWG | Network → AmneziaWG | загрузка `.conf`, ключи, параметры Jc/… |

### Watchdog

- На **Cudy**: `awg-client-watchdog` — при мёртвом handshake обновляет host-route и поднимает `wg0` (в режиме VPN).
- На **VPS**: `awg-peer-watchdog` — сброс пира с зависшей сессией (`remove` + `allowed-ips`).

## Адресация (по умолчанию)

| Роль | IP / сеть |
|------|-----------|
| VPS в туннеле | `10.9.0.1/24` |
| Cudy в туннеле | `10.9.0.2/24` |
| LAN Cudy | `192.168.10.0/24`, шлюз `192.168.10.1` |
| Endpoint | `VPS_IP:443/udp` |
| Режим трафика | `/etc/amnezia/traffic-mode` = `vpn` \| `wisp` |

Параметры маскировки AmneziaWG (`Jc`, `Jmin`, …) должны **совпадать** на VPS и на Cudy — файл `awg-params.env`.

## Дальше

1. [02-flash-cudy.md](02-flash-cudy.md) — прошивка  
2. [03-vps-amneziawg.md](03-vps-amneziawg.md) — сервер  
3. [04-connect-cudy.md](04-connect-cudy.md) — клиент и проверка  
4. [05-switch-wifi.md](05-switch-wifi.md) — смена uplink  
5. [06-traffic-mode.md](06-traffic-mode.md) — обычный / VPN  
6. [07-amneziawg-ui.md](07-amneziawg-ui.md) — LuCI AmneziaWG  
7. [08-tunnel-recovery.md](08-tunnel-recovery.md) — обрыв handshake
