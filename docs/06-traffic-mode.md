# Режим интернета: обычный WISP или VPN

Два режима на весь LAN — и Wi‑Fi `Travel-VPN`, и кабель в LAN-порт. Выбор чужой сети — отдельно, на странице **Смена Wi‑Fi**.

| Режим | Куда идёт трафик | Внешний IP |
|-------|------------------|------------|
| **Обычный** (`wisp`) | чужой Wi‑Fi, туннель выключен | IP провайдера uplink |
| **VPN** (`vpn`) | весь трафик в AmneziaWG, kill-switch | публичный IP VPS |

Файл на роутере: **`/etc/amnezia/traffic-mode`** (`wisp` или `vpn`). После перезагрузки режим сохраняется. Конфиг AmneziaWG и ключи при переключении не стираются.

## Как переключить

1. Подключиться к `Travel-VPN-*` или кабелем в LAN Cudy.
2. Открыть http://192.168.10.1
3. **Network → Режим интернета** или  
   http://192.168.10.1/cgi-bin/luci/admin/network/traffic-mode
4. Карточка **Обычный** или **VPN** → подтвердить.
5. Подождать 10–30 с.

### Что видно на странице

- Две карточки; у активного — метка **Сейчас**.
- Статистика каждые 5 с: uplink (SSID, сигнал, IP), в VPN — handshake и rx/tx, таблица клиентов LAN.
- Ссылка на **Смена Wi‑Fi**.

Сырой `awg show` — на **Network → Статус VPN**.

### Проверка

```sh
# на Cudy
cat /etc/amnezia/traffic-mode
ip -4 route show default
wget -qO- http://ifconfig.me/ip; echo
```

| Режим | `traffic-mode` | default | `ifconfig.me` |
|-------|----------------|---------|---------------|
| VPN | `vpn` | `dev wg0` | IP VPS |
| Обычный | `wisp` | через `phy*-sta0` (wwan) | IP провайдера |

**SSH-нюанс:** `awg-mode.sh set-wisp` / `set-vpn` на время `reload_config` может повесить интерактивный SSH на десятки секунд. Запускайте в фоне и читайте `traffic-mode` короткими вызовами.

```sh
/usr/libexec/awg-mode.sh status
/usr/libexec/awg-mode.sh set-wisp   # или set-vpn
```

## План тестов

| # | Шаг | Ожидание |
|---|-----|----------|
| 1 | Включить **VPN** | `ifconfig.me` = IP VPS, туннель жив |
| 2 | Включить **Обычный** | `wg0` down, интернет есть, IP провайдера |
| 3 | В обычном сменить Wi‑Fi | новый uplink, туннель не поднимается |
| 4 | В VPN сменить Wi‑Fi | uplink + туннель снова живы |
| 5 | Reboot в каждом режиме | `/etc/amnezia/traffic-mode` тот же; init `awg-traffic-mode` только чинит рассинхрон |
| 6 | Кабель LAN и Travel-VPN | одинаковое поведение в одном режиме |

## Установка / обновление с ПК

```sh
cd scripts/luci-mode
ROUTER=192.168.10.1 sh deploy-from-mac.sh
```

Скрипт ставит страницу и обновляет watchdog, hotplug endpoint и **Смена Wi‑Fi**, чтобы в обычном режиме они не поднимали `wg0`.

Подробнее про смену Wi‑Fi: [05-switch-wifi.md](05-switch-wifi.md).
