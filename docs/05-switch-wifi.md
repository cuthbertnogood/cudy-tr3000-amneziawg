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

Cudy может одновременно быть клиентом двух SSID (например 5 и 2,4 ГГц одного роутера). Это **не** удвоение скорости: один туннель `wg0`, при обрыве 5 ГГц hotplug переключает маршрут до VPS на 2,4 ГГц.

Сети **Travel-VPN** (точки доступа для телефонов) при смене чужого Wi‑Fi **не меняются**.

## Шаги в UI

1. **Найти сети**
2. Выбрать нужную в списке
3. Ввести пароль Wi‑Fi
4. **Подключить и поднять VPN**

Страница сама выберет `wwan5` или `wwan24` по диапазону сети. Туннель поднимается в фоне (10–30 с).

## Проверка

С телефона в `Travel-VPN-*`: откройте `https://ifconfig.me` — должен отображаться **VPS_IP**, не IP uplink-сети.

## Установка страницы (один раз)

С компьютера в LAN Cudy:

```sh
cd scripts/luci-wisp
export ROUTER=192.168.10.1
export ROUTER_SSH_PASS='ваш_пароль_root'   # опционально, если настроен sshpass
sh deploy-from-mac.sh
```

Без `sshpass` — обычный SSH по ключу:

```sh
scp -r scripts/luci-wisp/* root@192.168.10.1:/tmp/wisp-ui/
ssh root@192.168.10.1 'sh /tmp/wisp-ui/install-wisp-ui.sh'
```

## Если админка «недоступна»

- Подключитесь к **Travel-VPN** или по **кабелю** LAN.
- Отключите на ПК VPN-клиенты, которые перехватывают маршрут до `192.168.10.1`.

## CLI (без LuCI)

```sh
/usr/libexec/wisp-switch.sh scan
WISP_SSID='ИмяСети' WISP_KEY='пароль' /usr/libexec/wisp-switch.sh apply
/usr/libexec/wisp-switch.sh status
```
