# Прошивка Cudy TR3000 → OpenWrt

## Модель

| Параметр | Значение |
|----------|----------|
| Модель | **TR3000 EU v1.0** (128 МБ) |
| Target OpenWrt | `mediatek/filogic` |
| Device | **`cudy_tr3000-v1`** |
| **Не использовать** | `cudy_tr3000-256mb-v1` |

Серийный номер с наклейки: для некоторых партий (новый чип флеша) нужен OpenWrt **24.10.5 или новее**. Если сомневаетесь — не прошивайте старым образом.

## Файлы

| Шаг | Откуда |
|-----|--------|
| Intermediate (подписанный Cudy) | [Cudy OpenWrt FAQ](https://www.cudy.com/blogs/faq/openwrt-software-download) — **TR3000 v1** |
| Sysupgrade OpenWrt 24.10.5 | https://downloads.openwrt.org/releases/24.10.5/targets/mediatek/filogic/openwrt-24.10.5-mediatek-filogic-cudy_tr3000-v1-squashfs-sysupgrade.bin |

Подробнее: [artifacts/README.md](../artifacts/README.md).

## Подключение

1. ПК **кабелем** в **LAN** Cudy (не WAN).
2. Стоковая админка часто `http://192.168.10.1` — задайте пароль root, если просят.

## Шаг 1: Intermediate

1. В веб-UI стоковой прошивки: раздел прошивки / firmware.
2. Выберите **intermediate** `.bin` для TR3000 v1.
3. Дождитесь перезагрузки (~2 мин).
4. Админка может переехать на `http://192.168.1.1`, root без пароля — **сразу задайте пароль**.

## Шаг 2: OpenWrt sysupgrade

1. Откройте LuCI: `http://192.168.1.1`.
2. **System → Backup / Flash Firmware**.
3. Загрузите `openwrt-...-cudy_tr3000-v1-squashfs-sysupgrade.bin`.
4. **Снимите** «Keep settings» / сохранить настройки.
5. Flash, дождитесь reboot.

## Шаг 3: Базовая сеть

1. Подключитесь снова по кабелю; адрес LuCI часто `http://192.168.10.1` или `http://192.168.1.1` — смотрите индикацию/DHCP ПК.
2. Задайте **LAN** `192.168.10.1/24`, DHCP например `.100–.149` (можно позже сделает `setup-wisp.sh`).
3. Надёжный **пароль root**.

Проверка по SSH:

```sh
ssh root@192.168.10.1 'cat /etc/openwrt_release; uname -r'
# DISTRIB_RELEASE='24.10.5', ядро 6.6.x
```

## Дальше

Не настраивайте WISP вручную до чтения [04-connect-cudy.md](04-connect-cudy.md) — порядок: сначала VPS, ключи, kmod, затем `setup-wisp.sh` и `awg-apply.sh`.

Следующий шаг: [03-vps-amneziawg.md](03-vps-amneziawg.md) (сервер можно поднять параллельно с прошивкой).
