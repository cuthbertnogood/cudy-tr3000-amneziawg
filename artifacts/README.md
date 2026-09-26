# Артефакты прошивки и модуля

В репозитории **нет** готового кастомного образа OpenWrt «всё в одном». Нужны официальные файлы и собранный модуль ядра.

## OpenWrt (скачать с сайта)

| Файл | Назначение |
|------|------------|
| Cudy signed **intermediate** для TR3000 v1 | Первый шаг прошивки со стока |
| `openwrt-24.10.5-mediatek-filogic-cudy_tr3000-v1-squashfs-sysupgrade.bin` | Основной образ |

Ссылки и порядок: [docs/02-flash-cudy.md](../docs/02-flash-cudy.md).

Intermediate: [Cudy OpenWrt FAQ](https://www.cudy.com/blogs/faq/openwrt-software-download) — архив **TR3000 v1** (для новых партий флеша — актуальный intermediate, не архивный).

Sysupgrade:

https://downloads.openwrt.org/releases/24.10.5/targets/mediatek/filogic/openwrt-24.10.5-mediatek-filogic-cudy_tr3000-v1-squashfs-sysupgrade.bin

**Не ставить** образ `cudy_tr3000-256mb-v1` — это другая ревизия железа.

## Модуль `amneziawg.ko`

Соберите на Mac/Linux с Docker:

```sh
cd scripts/router
sh build-kmod-cudy-docker.sh
# → scripts/router/out/amneziawg-cudy.ko
```

Версия OpenWrt на роутере и SDK при сборке должны совпадать (`uname -r` на Cudy = vermagic в `.ko`).

Скопируйте на роутер:

```sh
scp out/amneziawg-cudy.ko root@192.168.10.1:/lib/modules/$(ssh root@192.168.10.1 uname -r)/amneziawg.ko
```

Готовый `.ko` в git не хранится (зависит от версии ядра). При желании можно прикладывать к **GitHub Releases** для конкретной версии OpenWrt.

## Userspace `awg`

На OpenWrt 24.10 обычно ставится через `opkg install amneziawg-tools` или `.ipk`, собранный тем же SDK, что и kmod.
