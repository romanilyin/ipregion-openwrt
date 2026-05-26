<p align="center">
  <img src="../luci-app-ipregion/htdocs/luci-static/resources/ipregion/logo.png" width="128" height="128" alt="Логотип IPRegion for OpenWrt">
</p>

# IPRegion for OpenWrt

CLI и LuCI-плагин для OpenWrt 25.12.4+, который проверяет, как GeoIP API, стриминговые сервисы, CDN и AI-провайдеры видят публичный IPv4/IPv6 маршрут роутера.

## Документация

- English: [../README.md](../README.md).
- Русский: этот файл.

## Назначение

IPRegion запускает диагностику на самом роутере. Можно проверять маршрут по умолчанию, конкретный сетевой интерфейс или SOCKS5-прокси. Результаты разных сервисов сравниваются в одной JSON-схеме и в LuCI-таблицах.

Пакеты:

- `ipregion`: CLI/backend на `ucode`.
- `luci-app-ipregion`: LuCI UI через узкий rpcd/ubus backend.

Это не Bash-обертка над upstream `vernette/ipregion`. Runtime не должен зависеть от `bash`, `jq`, `column` или `grep -P`; зависимости OpenWrt задаются в package `DEPENDS`.

## Состояние

Реализовано:

- CLI options, UCI-настройки, JSON schema v2 и compat JSON.
- Поиск внешнего IPv4/IPv6.
- Primary GeoIP-проверки из `services.json`.
- Custom/CDN handlers для набора сервисов из upstream.
- AI reachability проверки из `services-ai.json`.
- Инкрементальный прогресс и частичное обновление результата во время выполнения.
- LuCI status/settings pages, rpcd backend, ACL и gettext `.po/.pot` локализация.
- Runtime state, result и logs в `/tmp/run/ipregion/`.
- GitHub Actions CI для static checks и `ucode -c`.

Сборка в OpenWrt 25.12.4 SDK и smoke-тест на реальном роутере уже проверены. Для публичной установки одной командой ещё нужны опубликованные GitHub Release assets.

## Установка одной командой

На роутере:

```sh
wget -qO- https://raw.githubusercontent.com/romanilyin/ipregion-openwrt/main/install.sh | sh
```

Installer скачивает `ipregion*.apk` и `luci-app-ipregion*.apk` из последнего GitHub Release и ставит их через `apk`. Нужны опубликованные release assets; до первого release используйте сборку через SDK ниже.

Опции:

- `IPREGION_RELEASE=2026.5.26-1`: поставить конкретный GitHub release tag вместо `latest`.
- `IPREGION_INSTALL_LUCI=0`: поставить только CLI/backend пакет.
- `IPREGION_APK_UPDATE=0`: не запускать `apk update` перед установкой.

Пример с фиксированным release:

```sh
wget -qO- https://raw.githubusercontent.com/romanilyin/ipregion-openwrt/main/install.sh | IPREGION_RELEASE=2026.5.26-1 sh
```

## Сборка

Из OpenWrt 25.12.4+ buildroot или SDK:

```sh
make package/ipregion/compile V=s
make package/luci-app-ipregion/compile V=s
```

Установка готовых пакетов использует `apk`:

```sh
apk add --allow-untrusted ./ipregion-*.apk ./luci-app-ipregion-*.apk
```

Пример checkout для разработки в SDK/buildroot:

```sh
git clone https://github.com/romanilyin/ipregion-openwrt.git package/ipregion-openwrt
```

Helper для сборки через разные target SDK:

```sh
scripts/build-sdk-packages.sh mediatek/filogic
scripts/build-sdk-packages.sh x86/64
scripts/build-sdk-packages.sh ramips/mt7621
scripts/build-sdk-packages.sh ath79/generic
```

Пакеты script-only и собираются как `noarch`, но проверка нескольких SDK targets ловит проблемы feeds/package metadata. Если на локальной машине не хватает SDK prerequisites, лучше поставить недостающие build dependencies; только для локальных одноразовых smoke-тестов можно использовать `IPREGION_SKIP_PREREQ=1`.

## CLI

```sh
ipregion --help
ipregion --list-services --json
ipregion --self-test --json
ipregion --group primary --ipv4 --json
ipregion --group custom --ipv4 --json
ipregion --group cdn --ipv4 --json
ipregion --ipv6 --group primary --json
ipregion --interface wan --group primary --json
ipregion --proxy 127.0.0.1:1080 --proxy-dns remote --group custom --json
ipregion --group primary --geoip-mode route --json
ipregion ai --json
ipregion ai --category ai_china --json
ipregion ai --provider openai --proxy socks5h://127.0.0.1:1080 --json
```

## Группы проверок

- `all`: запускает все включенные GeoIP, проверки популярных сервисов и CDN.
- `primary` / GeoIP-сервисы: обращаются к публичным геолокационным API и реестрам, чтобы понять, какую страну они назначают IP-адресу роутера.
- `custom` / Популярные сервисы: обращаются к крупным платформам вроде Google, YouTube, Twitch, ChatGPT, Netflix и Spotify, чтобы увидеть, какой регион, доступ или страну их веб/API-эндпоинты возвращают для этого маршрута.
- `cdn` / CDN-сервисы: проверяют, до какого CDN edge или региона доходит роутер, например Cloudflare, YouTube или Netflix CDN.

Режимы GeoIP:

- `--geoip-mode lookup`: режим по умолчанию; сначала определяется egress IP роутера, затем GeoIP API проверяют именно этот IP. Это полезно для сравнения баз GeoIP по конкретному адресу.
- `--geoip-mode route`: поддерживаемые GeoIP API спрашиваются без подстановки IP, то есть они показывают страну, которую видят для самого запроса. Это полезно при split traffic, VPN policy и SOCKS5, когда generic IP discovery и нужный сервис могут идти разными маршрутами.

AI provider mode:

- `ipregion ai --json` запускает безопасные unauthenticated probes для OpenAI, Anthropic, Google Gemini, DeepSeek, Qwen, Kimi, Baidu Qianfan и Zhipu/GLM.
- `401`, `403`, `404`, `405` и `429` могут означать, что endpoint достигнут; JSON отдельно классифицирует это и DNS/TLS/timeout/network ошибки.
- API-ключи по умолчанию не запрашиваются и не сохраняются.

SOCKS5 DNS modes:

- `--proxy-dns remote`: `socks5h://`, DNS через прокси.
- `--proxy-dns local`: `socks5://`, DNS локально на роутере.

## Интерфейс и прокси

Используйте `--interface wan`, если нужно привязать curl к конкретному OpenWrt interface name. Имя интерфейса валидируется перед использованием.

Для policy-routing сценариев вроде mwan3, podkop, WARP или другого tunnel manager `curl --interface` не всегда полностью повторяет маршрут клиентского трафика. Самый надёжный способ проверить конкретный туннель или policy route — локальный SOCKS5 endpoint, который уже выходит через нужный маршрут.

Статусы результатов:

- `Denied`: сервис отказал в доступе для этого маршрута или региона.
- `Rate-limit`: endpoint ограничил запросы с IP роутера.
- `N/A`: проверка не смогла получить осмысленное значение для этой IP family или сервиса.

## LuCI

Меню:

- `Status -> IP Region`: запуск GeoIP/popular/CDN диагностики и AI reachability проверок, polling, таблицы результатов, download JSON.
- `Services -> IP Region`: настройки UCI по умолчанию.

Настройки задают defaults. Запуск проверок и просмотр результатов выполняются на странице `Status -> IP Region`; в настройках есть кнопка перехода туда.

Если после ручного deploy в LuCI появляется Access denied, перезапустите rpcd:

```sh
/etc/init.d/rpcd restart
```

## Локальная проверка на роутере

Скопируйте `.env.example` в `.env`. Пароль не хранится; `ssh` и `scp` будут спрашивать его интерактивно, пока не задан `OPENWRT_SSH_KEY`.

Значения по умолчанию:

```sh
OPENWRT_HOST=192.168.2.1
OPENWRT_USER=root
OPENWRT_SSH_PORT=22
```

Команды:

```sh
scripts/deploy-router.sh
scripts/test-router.sh
```

## Как попасть в официальные списки OpenWrt

Чтобы пакет появился в официальных OpenWrt package lists, его нужно принять в upstream feeds, после чего OpenWrt buildbots соберут пакеты и добавят их в индексы репозиториев.

- CLI/backend пакет нужно отправлять в `openwrt/packages`, вероятно как `net/ipregion`.
- LuCI-приложение нужно отправлять в `openwrt/luci`, вероятно как `applications/luci-app-ipregion`, вместе с `.po` переводами.
- Сборка должна быть воспроизводимой и без сетевых загрузок во время build; runtime dependencies должны быть только в `DEPENDS` / `LUCI_DEPENDS`.
- Нужны корректные `PKG_LICENSE`, SPDX headers, maintainer metadata и attribution upstream проекта.
- Пока нет native code, лучше сохранить пакеты `noarch`.
- Коммиты должны иметь `Signed-off-by` и стиль OpenWrt, например `ipregion: add package` и `luci-app-ipregion: add application`.
- Перед PR нужно проверить сборку на OpenWrt master и нужной stable branch.
- GitHub self-update button/installer, скорее всего, придётся отключить или убрать для official feed builds; официальные пакеты должны обновляться через OpenWrt package repositories, а не ставить untrusted APK из GitHub Release.
- После merge пакет появится в snapshots автоматически; для stable release нужен backport или следующий stable cycle.

## Приватность

Диагностика обращается к сторонним GeoIP, streaming и CDN endpoint-ам. Эти сервисы получают публичный IP роутера для каждой проверки. Debug/runtime logs остаются локально в `/tmp/run/ipregion/`; публичной загрузки логов нет.

## Attribution

Проект вдохновлён [`vernette/ipregion`](https://github.com/vernette/ipregion) и сохраняет совместимость по набору сервисов, но backend и LuCI-приложение переписаны под OpenWrt-native `ucode`.

## Маршрутизация

Плагин только делает outbound HTTPS-запросы. Он не должен менять firewall, nftables, mwan3, podkop, WARP или routing rules.
