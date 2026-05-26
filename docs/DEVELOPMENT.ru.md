# Разработка И Упаковка

Этот документ собирает технические детали для maintainers, contributors и будущей упаковки в OpenWrt feeds. Пользовательская установка и запуск описаны в [README.ru.md](README.ru.md).

## Scope

- Целевая версия OpenWrt: `25.12.4+`.
- Runtime-примеры используют `apk`.
- `ipregion` это CLI/backend пакет на `ucode`.
- `luci-app-ipregion` это LuCI-приложение через узкий rpcd/ubus API.
- `luci-i18n-ipregion-ru` содержит русский перевод LuCI.
- Пакеты остаются script-only/noarch, пока не появится native code.

Этот port намеренно не является оберткой вокруг upstream Bash-реализации. Runtime-зависимости на `bash`, `jq`, `column` и `grep -P` не используются; зависимости OpenWrt должны быть в package metadata.

## Локальные Static Checks

Запуск из корня репозитория:

```sh
scripts/ci/static-checks.sh
```

Static checks проверяют JSON catalogs, rpcd ACL/menu JSON, gettext coverage LuCI, JavaScript syntax и shell syntax.

Для локальных `ucode` syntax checks с UCI support:

```sh
scripts/ci/build-ucode.sh /tmp/ipregion-ucode-install
scripts/ci/ucode-checks.sh /tmp/ipregion-ucode-install/bin/ucode
```

CI workflow тоже запускает эти проверки, но billing или spending-limit проблемы GitHub account могут не дать hosted Actions jobs стартовать.

## SDK Build Smoke

Из OpenWrt 25.12.4+ buildroot или SDK, где доступен этот package feed:

```sh
make package/ipregion/compile V=s
make package/luci-app-ipregion/compile V=s
```

Пример checkout feed:

```sh
git clone https://github.com/romanilyin/ipregion-openwrt.git package/ipregion-openwrt
```

Helper для разных target SDK:

```sh
scripts/build-sdk-packages.sh mediatek/filogic
scripts/build-sdk-packages.sh x86/64
scripts/build-sdk-packages.sh ramips/mt7621
scripts/build-sdk-packages.sh ath79/generic
```

Пакеты noarch, но проверка нескольких SDK targets ловит проблемы feeds, dependencies и package metadata.

Если локальному одноразовому хосту не хватает OpenWrt SDK prerequisites, `IPREGION_SKIP_PREREQ=1` может обойти SDK prerequisite probing. Не используйте это как доказательство готовности official package; для реальной проверки нужно поставить недостающие SDK host dependencies.

## Router Smoke Testing

Локальные helper scripts читают optional `.env`, иначе используют значения development router:

```sh
OPENWRT_HOST=192.168.2.1
OPENWRT_USER=root
OPENWRT_SSH_PORT=22
```

Скопируйте `.env.example` в `.env` для локальных override. Файл `.env` должен оставаться untracked и не должен попадать в OpenWrt artifacts.

Текущий router login password-based; helper scripts дают `ssh` и `scp` запросить пароль интерактивно, если не задан `OPENWRT_SSH_KEY`.

Deploy и test helpers:

```sh
scripts/deploy-router.sh
scripts/test-router.sh
```

В OpenWrt/dropbear может не быть SFTP server, поэтому tooling иногда должен использовать legacy SCP mode.

Router smoke checks должны покрывать:

- `ipregion --self-test --json`
- обычные GeoIP/popular/CDN runs через CLI и ubus
- `ipregion ai --provider google_gemini --json`
- загрузку LuCI page после `rpcd` restart и `uhttpd` reload
- GeoIP режимы `lookup` и `route`
- SOCKS5 local DNS и remote DNS, если доступен proxy

## Runtime State

Runtime data остается локально в `/tmp/run/ipregion/`.

- regular state: `/tmp/run/ipregion/state.json`
- regular result: `/tmp/run/ipregion/result.json`
- regular log: `/tmp/run/ipregion/log.txt`
- AI state: `/tmp/run/ipregion/ai-state.json`
- AI result: `/tmp/run/ipregion/ai-result.json`
- AI log: `/tmp/run/ipregion/ai-log.txt`

Endpoint failures должны оставаться per-service и не должны прерывать весь run.

## LuCI И rpcd

- rpcd backend находится в `luci-app-ipregion/root/usr/share/rpcd/ucode/ipregion.uc`.
- Он возвращает `{ 'luci.ipregion': methods }`.
- ACL ubus object names должны совпадать с backend object.
- Не выдавайте generic exec access.
- LuCI strings должны использовать `_('...')`.
- Translation sources: `po/templates/ipregion.pot` и `po/ru/ipregion.po`.
- Service ids и raw JSON field names не переводятся.

## Security And Routing Constraints

- Валидируйте user-controlled `interface`, `proxy` и service/provider ids перед использованием в commands.
- Не добавляйте firewall, nftables, mwan3, podkop, WARP или routing changes.
- Это diagnostics-only приложение, которое только делает outbound HTTPS requests.
- SOCKS5 checks должны поддерживать local DNS через `socks5://` и remote DNS через `socks5h://`.
- Debug/log output должен оставаться локально в `/tmp/run/ipregion/`.

## Release Packaging

Public GitHub Release installer находится в корне репозитория: `install.sh`.

- Он читает GitHub Release metadata.
- Он скачивает `ipregion*.apk`, `luci-app-ipregion*.apk` и `luci-i18n-ipregion-ru*.apk`.
- Он устанавливает через `apk` и по умолчанию использует `--allow-untrusted`, потому что GitHub Release APK не из official OpenWrt package repository.
- Он поддерживает `IPREGION_RELEASE`, `IPREGION_INSTALL_LUCI`, `IPREGION_APK_UPDATE`, `IPREGION_REPO`, `IPREGION_GITHUB_API` и `IPREGION_APK_FLAGS`.

Перед публикацией release:

- запустить `scripts/ci/static-checks.sh`
- запустить `scripts/ci/ucode-checks.sh` с локально собранным `ucode`
- собрать packages в OpenWrt SDK
- выполнить focused router smoke tests
- проверить LuCI после hard refresh и `rpcd` restart

## Official OpenWrt Feeds

Подачу в official OpenWrt feeds сейчас намеренно не делаем.

Главный blocker это update/install behavior: official packages должны обновляться через OpenWrt package repositories, а не через установку untrusted APK из GitHub Releases. Перед upstream feed PR GitHub self-update button и installer integration нужно отключить, убрать или явно вынести за пределы official feed builds.

Когда будем готовить official feed work позже:

- CLI/backend пакет отправлять в `openwrt/packages`, вероятно как `net/ipregion`.
- LuCI app отправлять в `openwrt/luci`, вероятно как `applications/luci-app-ipregion`, вместе с `.po` переводами.
- Сборка должна быть reproducible и offline; все runtime dependencies должны быть объявлены в `DEPENDS` или `LUCI_DEPENDS`.
- `PKG_LICENSE`, SPDX headers, maintainer metadata и source attribution должны быть корректны.
- Пакеты должны оставаться noarch/script-only, пока не появится native code.
- В commits нужен `Signed-off-by`.
- Нужно соблюдать OpenWrt commit style, например `ipregion: add package` и `luci-app-ipregion: add application`.
- Перед PR нужна build-test проверка на current OpenWrt master и нужной stable branch.
- После merge пакеты появляются в snapshots автоматически; для stable release нужен backport или следующий stable release cycle.

## Attribution Notes

`vernette/ipregion` это upstream behavior reference для service intent и compatibility. Не переносите его Bash implementation напрямую.
