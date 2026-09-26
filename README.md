# Cudy TR3000 + AmneziaWG на своём VPS

Портативный VPN-шлюз: **Cudy TR3000** подключается к чужому Wi‑Fi (WISP), поднимает **AmneziaWG** до вашего **VPS**, раздаёт Wi‑Fi клиентам. Два режима трафика: **VPN** (kill-switch через туннель) и **Обычный** (напрямую через WISP).

Готовой «прошивки одним файлом» в репозитории нет: путь = официальный OpenWrt + модуль ядра + скрипты из этого репо.

## Схема (режим VPN)

```mermaid
flowchart TB
  subgraph uplink [Чужой Wi-Fi]
    U5[Uplink_5GHz]
    U24[Uplink_2.4GHz]
  end
  subgraph cudy [Cudy TR3000 OpenWrt]
    W5[wwan5 metric10]
    W24[wwan24 metric20]
    WG[wg0 AmneziaWG]
    AP[Travel-VPN AP]
    W5 --> WG
    W24 -.->|failover| WG
    AP --> WG
  end
  Phone[Телефон / ноутбук] --> AP
  U5 --> W5
  U24 --> W24
  WG -->|UDP 443| VPS[VPS_wg0]
  VPS --> Net[Internet]
```

| Узел | По умолчанию | Роль |
|------|----------------|------|
| VPS `wg0` | `10.9.0.1/24` | AmneziaWG-сервер, NAT в интернет |
| Cudy `wg0` | `10.9.0.2/24` | единственный пир в этом гайде |
| Cudy LAN | `192.168.10.1` | DHCP для кабеля и AP |
| WISP | `wwan5` + `wwan24` | Два uplink; failover, не суммирование скорости |

## Документация (под ключ)

| Шаг | Файл |
|-----|------|
| 1. Что умеет шлюз | [docs/01-overview.md](docs/01-overview.md) |
| 2. Прошить Cudy → OpenWrt | [docs/02-flash-cudy.md](docs/02-flash-cudy.md) |
| 3. Поднять AmneziaWG на VPS | [docs/03-vps-amneziawg.md](docs/03-vps-amneziawg.md) |
| 4. Связать Cudy с VPS | [docs/04-connect-cudy.md](docs/04-connect-cudy.md) |
| 5. Смена uplink Wi‑Fi | [docs/05-switch-wifi.md](docs/05-switch-wifi.md) |
| 6. Режим обычный / VPN | [docs/06-traffic-mode.md](docs/06-traffic-mode.md) |
| 7. Страницы AmneziaWG в LuCI | [docs/07-amneziawg-ui.md](docs/07-amneziawg-ui.md) |
| 8. Обрыв туннеля / watchdog | [docs/08-tunnel-recovery.md](docs/08-tunnel-recovery.md) |

Для развёртывания **агентом LLM** (Cursor / Codex и т.п.): [AGENTS.md](AGENTS.md) — порядок, команды, env, критерии успеха и запреты.

## Быстрый порядок

1. Прошить **Cudy TR3000 EU v1** (не 256 МБ): intermediate → OpenWrt **24.10.5+** → LAN `192.168.10.1`.
2. На **VPS** (Ubuntu/Debian): `scripts/vps/awg-server.sh` с `CLIENT_PUB` с роутера; по желанию `awg-peer-watchdog.sh --install`.
3. На **Cudy**: kmod, `setup-wisp.sh`, `awg-apply.sh`, LuCI «Смена Wi‑Fi», «AmneziaWG», «Режим интернета».
4. Проверка в VPN: `EXPECTED_IP=<публичный_IP_VPS> sh scripts/router/verify-awg.sh`.

Переменные: `scripts/router/router.env.example`, `scripts/vps/awg-params.env.example`.

## Состав репозитория

```
scripts/vps/          — сервер AmneziaWG + peer-watchdog
scripts/router/       — WISP, клиент AWG, hotplug, client-watchdog, kmod
scripts/luci-wisp/    — страница «Смена Wi‑Fi»
scripts/luci-awg/     — страницы «Статус VPN» / «AmneziaWG»
scripts/luci-mode/    — страница «Режим интернета» (обычный / VPN)
artifacts/            — откуда качать OpenWrt, куда класть .ko
```

## Железо

- **Cudy TR3000 EU v1.0**, 128 МБ — target `cudy_tr3000-v1`
- Для партий с новым флешем нужен OpenWrt **24.10.5 или новее** (см. док прошивки)

## Лицензия

MIT — см. [LICENSE](LICENSE).
