# Смена Wi‑Fi (uplink)

После установки LuCI-страницы (см. [04-connect-cudy.md](04-connect-cudy.md)):

**Network → Смена Wi‑Fi**

или

`http://192.168.10.1/cgi-bin/luci/admin/network/wisp`

Логин: `root` и пароль админки роутера.

## Два WISP

| Радио | Интерфейс | Роль |
|-------|-----------|------|
| 5 ГГц | `wwan5` | основной uplink (metric 10) |
| 2,4 ГГц | `wwan24` | запасной (metric 20) |

Cudy может одновременно быть клиентом двух SSID (например 5 и 2,4 ГГц одного роутера). Это **не** удвоение скорости: один путь uplink; при обрыве 5 ГГц hotplug переключает маршрут до VPS на 2,4 ГГц.

Сети **Travel-VPN** (точки доступа для телефонов) при смене чужого Wi‑Fi **не меняются**.

На странице можно выбрать режим band: **только 5** / **только 2,4** / **оба**. При «оба» живой 5 ГГц всегда предпочтительнее.

## Режимы трафика и кнопка

Смена Wi‑Fi **не** переключает режим интернета (обычный / VPN). Режим интернета **не** сбрасывает выбранный SSID.

| | Обычный | VPN |
|--|---------|-----|
| Скан / выбор SSID / пароль / band | да | да |
| Поднять `wwan5`/`wwan24` | да | да |
| Host-route до VPS | не нужен | да |
| `ifup wg0` | нет | да |
| Кнопка | **Подключить** | **Подключить и поднять VPN** |

Как сменить режим: [06-traffic-mode.md](06-traffic-mode.md).

## Шаги в UI

1. Выберите **режим uplink** (5 / 2,4 / оба) → **Применить режим**.
2. **Найти сети** (скан 20–40 с, в фоне — без XHR timeout).
3. Выбрать сеть → пароль → **Подключить** (или «…и поднять VPN»).

Страница сама выберет `wwan5` или `wwan24` по диапазону сети.

## Проверка

С телефона в `Travel-VPN-*`:

- в режиме **VPN**: `https://ifconfig.me` → публичный IP VPS;
- в режиме **Обычный**: IP провайдера uplink-сети.

## Установка страницы

```sh
cd scripts/luci-wisp
export ROUTER=192.168.10.1
# опционально: export ROUTER_SSH_PASS='пароль_root'
sh deploy-from-mac.sh
```

Без `sshpass`:

```sh
scp scripts/luci-wisp/{wisp-switch.sh,wisp-scan-worker.sh,switch.js,luci-app-wisp-*.json,install-wisp-ui.sh} \
  root@192.168.10.1:/tmp/wisp-ui/
ssh root@192.168.10.1 'sh /tmp/wisp-ui/install-wisp-ui.sh'
```

После установки **Режима интернета** (`scripts/luci-mode/deploy-from-mac.sh`) страница Смена Wi‑Fi становится mode-aware (подписи и `ifup wg0` только в VPN).

## Если админка «недоступна»

- Подключитесь к **Travel-VPN** или по **кабелю** LAN.
- Отключите на ПК VPN-клиенты, которые перехватывают маршрут до `192.168.10.1`.

## CLI (без LuCI)

```sh
/usr/libexec/wisp-switch.sh scan
WISP_SSID='ИмяСети' WISP_KEY='пароль' /usr/libexec/wisp-switch.sh apply
/usr/libexec/wisp-switch.sh status
```
