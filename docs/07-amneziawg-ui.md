# LuCI: Статус VPN и AmneziaWG

| Страница | Меню | URL |
|----------|-------|-----|
| Статус и статистика | **Network → Статус VPN** | http://192.168.10.1/cgi-bin/luci/admin/network/amneziawg-status |
| Настройки / `.conf` | **Network → AmneziaWG** | http://192.168.10.1/cgi-bin/luci/admin/network/amneziawg |

Смена uplink: [05-switch-wifi.md](05-switch-wifi.md).  
Обычный / VPN: [06-traffic-mode.md](06-traffic-mode.md).

## Статус VPN

Автообновление каждые 5 с:

- туннель работает / не поднят (handshake моложе ~2 мин);
- endpoint, адрес туннеля, MTU, keepalive;
- трафик принято / отправлено;
- public keys, default route, маршрут до endpoint;
- uplink WISP (5 / 2,4 ГГц);
- сырой `awg show`.

Краткий статус также на страницах **AmneziaWG** и **Смена Wi‑Fi**.

## Где лежит конфиг

| Что | Где |
|-----|-----|
| Рабочий конфиг | `/etc/config/network` — `wg0` (`proto amneziawg`) и пир `wgvps` / `wgserver` |
| Приватный ключ | `/etc/wireguard/wg0.key` |
| Режим трафика | `/etc/amnezia/traffic-mode` |
| IP endpoint для host-route | `/etc/amnezia/endpoint` (+ hotplug `99-awg-endpoint`) |

Отдельного `wg0.conf` на клиенте нет — на роутере всё через UCI.

## Страница настроек

1. Зайти из `Travel-VPN` или по кабелю (`192.168.10.1`).
2. **Network → AmneziaWG**.
3. Загрузить `.conf` (`[Interface]` / `[Peer]` + `Jc`/`Jmin`/…) или заполнить поля вручную.
4. **Применить** — UCI, host-route, `ifup wg0`.
5. Через 15–30 с — статус: handshake живой; с телефона `ifconfig.me` = IP VPS.

**Private key** в форме можно оставить пустым — текущий ключ на роутере не трогается.

Параметры маскировки (`Jc`, `Jmin`, `Jmax`, `S1`, `S2`, `H1`–`H4`) **должны совпадать с сервером**.

## Смена на другой AmneziaWG-сервер

1. На новом сервере добавить пир (текущий client public key или ключ из нового `.conf`).
2. Взять endpoint, порт, server public key, `Address`, Jc/…
3. На Cudy: загрузить `.conf` → **Применить**.
4. Проверить статус и `ifconfig.me`.

Kill-switch действует только в режиме **VPN**. В **Обычном** трафик идёт через WISP — [06-traffic-mode.md](06-traffic-mode.md).

Если WISP жив, а handshake мёртв — [08-tunnel-recovery.md](08-tunnel-recovery.md).

## Установка с ПК

```sh
cd scripts/luci-awg
ROUTER=192.168.10.1 sh deploy-from-mac.sh
```

## Пример `.conf`

```ini
[Interface]
PrivateKey = <client private>
Address = 10.9.0.2/24
DNS = 1.1.1.1
MTU = 1280
Jc = 4
Jmin = 40
Jmax = 70
S1 = 0
S2 = 0
H1 = 1
H2 = 2
H3 = 3
H4 = 4

[Peer]
PublicKey = <server public>
Endpoint = VPS_IP:443
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```
