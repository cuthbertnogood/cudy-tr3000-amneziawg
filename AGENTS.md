# AGENTS.md — runbook для LLM-агентов

Источник правды по шагам: `docs/01`–`08` и `README.md`. Этот файл — сжатый порядок действий, команды и стоп-условия. Не дублируй длинные гайды в ответ пользователю — выполняй и ссылайся на файлы.

## Цель

Поднять travel-шлюз: **Cudy TR3000 (OpenWrt 24.10.5+)** + **свой VPS (AmneziaWG)** + dual-WISP + LuCI (смена Wi‑Fi, AmneziaWG, режим обычный/VPN). Готового `.bin` «всё в одном» нет.

Дефолты: LAN `192.168.10.1`, туннель `10.9.0.1` (VPS) / `10.9.0.2` (Cudy), UDP `443`, AP `Travel-VPN-*`.

## Перед стартом — спроси у пользователя

Не выдумывай:

| Нужно | Пример |
|-------|--------|
| Публичный IP VPS | `WG_ENDPOINT` |
| SSH на VPS | host, user, ключ |
| Доступ к Cudy | кабель / `Travel-VPN`, `root` пароль |
| Uplink Wi‑Fi | SSID 5 / 2.4, пароль |
| Пароль AP Travel-VPN | `AP_KEY` |
| Уже есть ключи / пир? | не перегенерировать без спроса |

Секреты только в env / локальных файлах вне git. **Не** коммить `awg-params.env`, `router.env`, `.ko`, ключи. **Не** печатать private key в чат.

## Порядок (строго)

```text
1 flash Cudy          → docs/02-flash-cudy.md        (часто вручную в браузере)
2 awg-params.env      → один набор Jc/… на VPS и Cudy
3 ключ клиента Cudy   → первый проход awg-apply.sh → CLIENT_PUB
4 VPS server + peer   → scripts/vps/awg-server.sh (+ peer-watchdog)
5 kmod + WISP + AWG   → build-kmod, setup-wisp, awg-apply (2-й проход)
6 LuCI                → luci-wisp → luci-awg → luci-mode
7 verify              → verify-awg.sh, traffic-mode
```

Прошивку (шаг 1) агент обычно **не** делает сам — дай чеклист из `docs/02`, дождись подтверждения OpenWrt + LAN `192.168.10.1`.

## Env

```sh
# из корня репо
cp scripts/vps/awg-params.env.example scripts/vps/awg-params.env
cp scripts/router/awg-params.env.example scripts/router/awg-params.env
# синхронизируй Jc/Jmin/… между ними

cp scripts/router/router.env.example scripts/router/router.env
# заполни WG_ENDPOINT, WISP*, AP_KEY — потом: set -a; . scripts/router/router.env; set +a
```

Игнор git уже содержит `*.env` (кроме `*.example`), `*.ko`, `credentials.*`.

## Команды (копируй как есть)

Подставь значения пользователя. `ROUTER=192.168.10.1`. Опционально `ROUTER_SSH_PASS=…` для `sshpass`.

### A. Ключ клиента на Cudy (после OpenWrt + kmod/tools)

```sh
scp -r scripts/router/* root@${ROUTER}:/tmp/router/
scp scripts/router/awg-params.env root@${ROUTER}:/tmp/router/
ssh root@${ROUTER} 'cd /tmp/router && sh awg-apply.sh'
# сохранить CLIENT_PUB → на VPS
```

### B. VPS

```sh
scp scripts/vps/* root@${VPS}:/root/cudy-awg/
ssh root@${VPS} 'cd /root/cudy-awg && cp -n awg-params.env.example awg-params.env'
ssh root@${VPS} "cd /root/cudy-awg && CLIENT_PUB='…' EXT_IF=eth0 sh awg-server.sh"
ssh root@${VPS} 'cd /root/cudy-awg && sh awg-peer-watchdog.sh --install'
# запомнить AWG_SERVER_PUBKEY с сервера
```

### C. kmod (ПК с Docker) + WISP + клиент

```sh
cd scripts/router && sh build-kmod-cudy-docker.sh
KVER=$(ssh root@${ROUTER} uname -r)
scp out/amneziawg-cudy.ko root@${ROUTER}:/lib/modules/${KVER}/amneziawg.ko
ssh root@${ROUTER} 'depmod -a; insmod /lib/modules/$(uname -r)/amneziawg.ko; echo amneziawg > /etc/modules.d/99-amneziawg'

ssh root@${ROUTER} "cd /tmp/router && \
  WISP5_SSID='…' WISP24_SSID='…' WISP_KEY='…' AP_KEY='…' sh setup-wisp.sh"

ssh root@${ROUTER} "cd /tmp/router && \
  WG_ENDPOINT='…' AWG_SERVER_PUBKEY='…' sh awg-apply.sh"
```

### D. LuCI (ПК в LAN / Travel-VPN)

```sh
cd scripts/luci-wisp && ROUTER=${ROUTER} sh deploy-from-mac.sh
cd ../luci-awg  && ROUTER=${ROUTER} sh deploy-from-mac.sh
cd ../luci-mode && ROUTER=${ROUTER} sh deploy-from-mac.sh
```

`luci-mode` также обновляет mode-aware WISP, hotplug и `awg-client-watchdog`.

### E. Проверка

```sh
EXPECTED_IP=${WG_ENDPOINT} ROUTER=${ROUTER} sh scripts/router/verify-awg.sh
ssh root@${ROUTER} 'cat /etc/amnezia/traffic-mode; awg show wg0; wget -qO- http://ifconfig.me; echo'
```

Режимы:

```sh
ssh root@${ROUTER} '/usr/libexec/awg-mode.sh status'
# set-wisp / set-vpn могут надолго зависнуть SSH — запускай в фоне, потом короткий cat traffic-mode
```

## Критерии успеха

| Режим | Ожидание |
|-------|----------|
| VPN (`traffic-mode=vpn`) | handshake жив; default через `wg0`; `ifconfig.me` = публичный IP VPS; без туннеля у клиентов интернета нет |
| Обычный (`wisp`) | `wg0` down; default через WISP; `ifconfig.me` = IP провайдера uplink |
| Reboot | файл `/etc/amnezia/traffic-mode` тот же |

## Типичные сбои

| Симптом | Действие |
|---------|----------|
| Handshake есть, egress не VPS | host-route: `ip route get $WG_ENDPOINT` через `phy*-sta*`, не `wg0` |
| 0 B received, WISP жив | docs/08 — peer-watchdog на VPS; ручной `awg set peer … remove` + `allowed-ips` |
| kmod не грузится | vermagic ≠ `uname -r` — пересобрать kmod |
| Смена Wi‑Fi снова поднимает VPN в обычном | переустановить `luci-mode` deploy |
| Админка «недоступна» | ПК должен быть в Travel-VPN или на кабеле LAN Cudy |

## Запреты для агента

- Не коммитить секреты, реальные IP/SSID пользователя, private keys.
- Не менять `CLIENT_IP` / не пересоздавать ключи, если пользователь сказал «оставить».
- Не открывать лишние порты на VPS; не снимать kill-switch в режиме VPN без явной просьбы.
- Не править чужие пиры на VPS, кроме Cudy из этого гайда.
- Flash / factory reset — только с явным подтверждением пользователя.

## Карта репо

```
docs/01–08          — человеческие гайды
scripts/vps/        — awg-server, awg-add-peer, awg-peer-watchdog
scripts/router/     — setup-wisp, awg-apply, hotplug, verify, client-watchdog, kmod
scripts/luci-wisp/  — Смена Wi‑Fi
scripts/luci-awg/   — Статус VPN / AmneziaWG
scripts/luci-mode/  — Режим интернета
artifacts/          — ссылки на OpenWrt, без готового образа
```
