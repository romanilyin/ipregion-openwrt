<div align="center">

<img src="../luci-app-ipregion/htdocs/luci-static/resources/ipregion/logo.png" width="128" height="128" alt="Логотип IPRegion for OpenWrt">

# IPRegion for OpenWrt

**Диагностика маршрута, региона, CDN, AI endpoint-ов и целостности DNS для OpenWrt-роутеров.**

[English](../README.md) |
[Русский](./README.ru.md) |
[Development](./DEVELOPMENT.md) |
[Разработка](./DEVELOPMENT.ru.md) |
[Releases](https://github.com/romanilyin/ipregion-openwrt/releases)

[![CI](https://github.com/romanilyin/ipregion-openwrt/actions/workflows/ci.yml/badge.svg)](https://github.com/romanilyin/ipregion-openwrt/actions/workflows/ci.yml)

<p>
  <a href="#что-делает"><img src="./assets/readme/cards/openwrt.svg" alt="OpenWrt" height="52"></a>
  <a href="#cli"><img src="./assets/readme/cards/cli.svg" alt="CLI" height="52"></a>
  <a href="#luci"><img src="./assets/readme/cards/luci.svg" alt="LuCI" height="52"></a>
  <a href="#установка-apk"><img src="./assets/readme/cards/apk.svg" alt="APK packages" height="52"></a>
  <a href="#установка-ipk"><img src="./assets/readme/cards/ipk.svg" alt="IPK packages" height="52"></a>
</p>

</div>

IPRegion это CLI и LuCI-приложение для OpenWrt, которое проверяет, как GeoIP API, популярные сервисы, CDN endpoint-ы и AI-провайдеры видят маршрут роутера, а также сравнивает ответы публичных DNS через UDP, TCP, DoH и DoT.

Проверенная runtime-цель текущей версии: OpenWrt 25.12.1+ с `apk`. Поддержка OpenWrt 24.10.* остается экспериментальной, а ее installer закреплен на более старом проверенном релизе пакетов.

## Что Делает

IPRegion запускает диагностику на самом роутере и показывает результаты разных сервисов в одном UI и JSON.

- GeoIP-проверки показывают, какую страну публичные геолокационные API назначают маршруту.
- Проверки популярных сервисов показывают регион, доступ, rate-limit или отказ от крупных платформ.
- CDN-проверки показывают, до какого CDN edge или региона доходит роутер.
- AI-проверки безопасно проверяют реальные домены web- и API-endpoint-ов AI без авторизации.
- Проверки безопасности DNS сравнивают ответы UDP/53, TCP/53, DoH и DoT от Google, Cloudflare, Quad9, AdGuard DNS и Яндекс DNS; при наличии также проверяется открытый DNS активного интерфейса.
- Проверки могут идти через маршрут по умолчанию, выбранный OpenWrt-интерфейс или SOCKS5-прокси.

Пакеты:

- `ipregion`: CLI/backend диагностики на `ucode`.
- `ipregion-dns-helper`: небольшой architecture-specific helper транспортов UDP, TCP и DoT с проверкой сертификата.
- `luci-app-ipregion`: LuCI UI в `Status -> IP Region`.
- `luci-i18n-ipregion-ru`: русский перевод LuCI.

Release-пакеты `ipregion`, `luci-app-ipregion` и `luci-i18n-ipregion-ru` собираются как `noarch`. Нативный `ipregion-dns-helper` собирается отдельно для каждой package architecture OpenWrt и использует уже установленную для IPRegion зависимость `libcurl`. Текущие APK assets поддерживают `aarch64_cortex-a53`, `x86_64`, `mipsel_24kc` и `mips_24kc`. Закрепленный legacy IPK release предназначен для OpenWrt 24.10.*.

## Скриншоты

<table>
  <tr>
    <td width="50%"><img src="screens/ru/screen_main_25_12_4.png" alt="Обзор страницы IPRegion в LuCI"></td>
    <td width="50%"><img src="screens/ru/screen_geoip_direct_25_12_4.png" alt="Результаты прямой GeoIP-проверки"></td>
  </tr>
  <tr>
    <td width="50%"><img src="screens/ru/screen_services_route_25_12_4.png" alt="Проверки популярных сервисов через маршрут"></td>
    <td width="50%"><img src="screens/ru/screen_cdn_route_25_12_4.png" alt="Проверки CDN через маршрут"></td>
  </tr>
  <tr>
    <td colspan="2"><img src="screens/ru/screen_ai_25_12_2.jpg" alt="Проверки AI-провайдеров"></td>
  </tr>
</table>

## Установка APK

Запустите на роутере с OpenWrt 25.12.1+:

```sh
wget -qO- https://raw.githubusercontent.com/romanilyin/ipregion-openwrt/main/install.sh | sh
```

Installer определяет `DISTRIB_ARCH`, скачивает соответствующий `ipregion-dns-helper-<architecture>.apk` и общие assets `ipregion*.apk`, `luci-app-ipregion*.apk`, `luci-i18n-ipregion-ru*.apk` из последнего GitHub Release и ставит их через `apk`.

Для установки нужна одна из перечисленных выше package architectures. Для других архитектур OpenWrt требуется отдельно собрать и опубликовать APK `ipregion-dns-helper`.

Release tags используют формат `YYYY.M.D-N`. В metadata пакета OpenWrt та же ревизия отображается как `YYYY.M.D-rN`, где `r` является стандартным маркером `PKG_RELEASE`.

Опции APK installer:

- `IPREGION_RELEASE=2026.9.2-2`: поставить конкретный GitHub release tag вместо `latest`.
- `IPREGION_INSTALL_LUCI=0`: поставить только CLI/backend пакет.
- `IPREGION_APK_UPDATE=0`: не запускать `apk update` перед установкой.
- `IPREGION_DOWNLOAD_RETRIES=5`: увеличить число повторов для GitHub metadata и APK downloads.
- `IPREGION_PACKAGE_ARCH=aarch64_cortex-a53`: переопределить package architecture для apk-based производной OpenWrt.

Пример с фиксированным release:

```sh
wget -qO- https://raw.githubusercontent.com/romanilyin/ipregion-openwrt/main/install.sh | IPREGION_RELEASE=2026.9.2-2 sh
```

Ручная установка скачанных APK:

```sh
. /etc/openwrt_release
apk add --allow-untrusted "./ipregion-dns-helper-${DISTRIB_ARCH}.apk" ./ipregion.apk ./luci-app-ipregion.apk ./luci-i18n-ipregion-ru.apk
```

## Установка IPK

Запустите на роутере с OpenWrt 24.10.*:

```sh
wget -qO- https://raw.githubusercontent.com/romanilyin/ipregion-openwrt/main/install-ipk.sh | sh
```

Экспериментальный IPK installer по умолчанию использует последний релиз, проверенный на реальном OpenWrt 24.10, `2026.5.28-1`, и ставит его assets `ipregion*.ipk`, `luci-app-ipregion*.ipk` и `luci-i18n-ipregion-ru*.ipk` через `opkg`. Текущее разделение пакетов с нативным helper пока не поддерживается этим installer. Задавайте `IPREGION_RELEASE` только для релиза, в котором явно опубликован совместимый и проверенный набор IPK assets.

Ручная установка скачанных IPK:

```sh
opkg install ./ipregion*.ipk ./luci-app-ipregion*.ipk ./luci-i18n-ipregion-ru*.ipk
```

## LuCI

Откройте `Status -> IP Region` в LuCI.

- Запускайте GeoIP, popular service, CDN, единую проверку целостности DNS и AI endpoint проверки с одной страницы.
- Выбирайте IP mode, interface, SOCKS5 proxy, timeout и GeoIP mode.
- Настройте несколько профилей SOCKS5 proxy в `Services -> IP Region`, включая локальный или удаленный DNS для каждого профиля, затем выбирайте нужный профиль на странице Status.
- Задавайте реальную страну, чтобы совпадающие значения подсвечивались оранжевым, а отличающиеся - синим.
- AI-проверки показывают отдельные строки IPv4 и IPv6 для каждого провайдера в режиме `IPv4 и IPv6`; недоступные транспорты отображаются явно.
- Смотрите прогресс во время выполнения.
- Скачивайте исходный JSON или копируйте безопасные для публикации Markdown-таблицы. Markdown не содержит исходные IP-адреса, endpoint-ы прокси и идентификаторы маршрута.
- Обновляйте пакет из GitHub Releases через карточку версии; защита от downgrade не даст установить более старый latest release.
- Откройте `Services -> IP Region` для UCI-настроек по умолчанию.
- Страница настроек показывает размер скачиваемого APK и установленный размер каждого пакета IPRegion. Там же можно удалить устаревший `knot-dig`, оставшийся от прежнего релиза.

## CLI

```sh
ipregion --help
ipregion --list-services --json
ipregion --self-test --json
ipregion --group primary --ipv4 --json
ipregion --group custom --ipv4 --json
ipregion --group cdn --ipv4 --json
ipregion --group primary --geoip-mode route --json
ipregion --interface wan --group primary --json
ipregion --proxy 127.0.0.1:1080 --proxy-dns remote --group custom --json
ipregion ai --json
ipregion ai --provider google_gemini --json
ipregion ai --provider google_gemini_web --json
ipregion dns --json
ipregion dns --provider google --transport all --ip-mode ipv4 --json
ipregion dns --provider interface_dns --transport plain --ip-mode ipv4 --json
```

## Режимы Проверок

- `--group all`: все включенные GeoIP, popular service и CDN проверки.
- `--group primary`: GeoIP-сервисы.
- `--group custom`: популярные сервисы.
- `--group cdn`: CDN-сервисы.
- `--geoip-mode lookup`: сначала определить egress IP роутера, затем попросить GeoIP API проверить этот IP.
- `--geoip-mode route`: спросить поддерживаемые GeoIP API, какую страну они видят для самого запроса.
- `ipregion ai --json`: безопасно проверить web/API endpoint-ы AI-провайдеров без хранения или запроса API-ключей.
- `ipregion ai --ip-mode both --json`: проверить каждого выбранного AI-провайдера отдельными IPv4 и IPv6 probe.
- `ipregion dns --json`: одной командой проверить UDP/53, TCP/53, DoH и DoT и сравнить коды и содержимое ответов.
- `ipregion dns --dns-name example.com --dns-type A --json`: проверить все DNS-транспорты для валидированного доменного имени и типа записи.
- `--transport plain`, `udp`, `tcp`, `doh` или `dot`: выполнить выбранные DNS-проверки; legacy-значение `both` остается парой DoH+DoT.

Для SOCKS5 proxy checks:

- `--proxy-dns remote`: использует `socks5h://`.
- `--proxy-dns local`: использует `socks5://`.

## Примечания

- `401`, `403`, `404`, `405` и `429` в AI mode могут означать, что endpoint достигнут; DNS, TLS, timeout и network failures классифицируются отдельно.
- Google Gemini Web использует `gemini.google.com`, а отдельная проверка Gemini API использует `generativelanguage.googleapis.com`. Domain-based split routing должен охватывать каждый hostname, который требуется направлять в VPN.
- Проверки публичных DNS подключаются к опубликованным IP резолверов; DoH и DoT дополнительно проверяют TLS-имя провайдера. DNS-адреса интерфейса читаются из выбранного или активного default-интерфейса OpenWrt и проверяются только через UDP/TCP.
- UDP, TCP и DoT используют небольшой нативный DNS helper IPRegion. DoT проверяет CA, hostname и SNI через уже имеющийся TLS backend `libcurl`; `knot-dig` не требуется.
- DNS mode игнорирует сохраненный в UCI proxy и отклоняет явный `--proxy`; DoH привязывается к выбранному интерфейсу, а UDP, TCP и DoT - к исходному адресу этого интерфейса.
- DNS mode `auto` предпочитает доступный IPv4 default route и переключается на IPv6 на IPv6-only роутерах; для явной проверки обоих используйте `--ip-mode both`.
- Результат `вероятен перехват` требует расхождения кода ответа с аутентифицированным DNS. Совпадающие ответы означают только отсутствие обнаруженного расхождения, а различия только в адресах остаются неоднозначными из-за допустимых вариаций CDN.
- При domain-based split routing общий egress IP может отличаться от маршрута конкретного сервиса или AI endpoint domain.
- Для policy-routing сценариев локальный SOCKS5 endpoint, который уже выходит через нужный туннель, обычно самый надежный объект диагностики.

## Приватность И Scope

Диагностика обращается к сторонним GeoIP, streaming, CDN, AI и публичным DNS endpoint-ам. Эти сервисы получают публичный IP роутера для каждой проверки.

Runtime state, results и logs остаются локально в `/tmp/run/ipregion/`.

IPRegion только диагностирует. Он не добавляет и не меняет firewall, nftables, mwan3, podkop, WARP или routing rules.

## Attribution

Проект вдохновлен [`vernette/ipregion`](https://github.com/vernette/ipregion) и сохраняет совместимость по набору сервисов, но backend и LuCI-приложение переписаны под OpenWrt-native `ucode`.
