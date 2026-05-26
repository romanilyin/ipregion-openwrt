<p align="center">
  <img src="luci-app-ipregion/htdocs/luci-static/resources/ipregion/logo.png" width="128" height="128" alt="IPRegion for OpenWrt logo">
</p>

# IPRegion for OpenWrt

[![CI](https://github.com/romanilyin/ipregion-openwrt/actions/workflows/ci.yml/badge.svg)](https://github.com/romanilyin/ipregion-openwrt/actions/workflows/ci.yml)

OpenWrt 25.12.4+ CLI and LuCI plugin for checking how GeoIP APIs, streaming platforms, CDN endpoints and AI providers see your router's public IPv4/IPv6 route.

## Localized Docs

- English: this README.
- Russian: [docs/README.ru.md](docs/README.ru.md).

## What It Does

IPRegion runs diagnostics from the router itself, optionally through a selected network interface or SOCKS5 proxy. It compares results from multiple providers and shows whether services report the same country, deny access, rate-limit requests or fail independently.

Packages:

- `ipregion`: CLI/backend diagnostics in `ucode`.
- `luci-app-ipregion`: LuCI UI using a narrow rpcd/ubus backend.

This port is intentionally not a Bash wrapper around upstream `vernette/ipregion`. It avoids runtime dependencies on `bash`, `jq`, `column`, and `grep -P`; OpenWrt dependencies belong in package `DEPENDS`.

## Status

Implemented:

- CLI options, UCI merge, JSON result schema v2 and compat JSON.
- External IPv4/IPv6 discovery.
- Generic GeoIP primary checks from `services.json`.
- Custom and CDN handlers for the upstream service set, with per-service failures isolated.
- AI provider reachability checks from `services-ai.json`.
- Incremental runtime progress and partial result updates while checks are running.
- LuCI status/settings pages, rpcd backend, ACL, and gettext `.po/.pot` localization.
- Runtime state, result and logs under `/tmp/run/ipregion/`.
- GitHub Actions CI for static checks and `ucode` syntax checks.

Verified with the OpenWrt 25.12.4 SDK and a real router smoke test. Public GitHub Release assets are available for one-line install/update.

## One-Line Install

On the router:

```sh
wget -qO- https://raw.githubusercontent.com/romanilyin/ipregion-openwrt/main/install.sh | sh
```

The installer downloads `ipregion*.apk`, `luci-app-ipregion*.apk` and `luci-i18n-ipregion-ru*.apk` from the latest GitHub Release and installs them with `apk`.

Options:

- `IPREGION_RELEASE=2026.5.26-1`: install a specific GitHub release tag instead of `latest`.
- `IPREGION_INSTALL_LUCI=0`: install only the CLI/backend package.
- `IPREGION_APK_UPDATE=0`: skip `apk update` before installation.

Example with a pinned release:

```sh
wget -qO- https://raw.githubusercontent.com/romanilyin/ipregion-openwrt/main/install.sh | IPREGION_RELEASE=2026.5.26-1 sh
```

## Build Smoke

From an OpenWrt 25.12.4+ buildroot or SDK with this package feed available:

```sh
make package/ipregion/compile V=s
make package/luci-app-ipregion/compile V=s
```

Runtime installation examples use `apk`:

```sh
apk add --allow-untrusted ./ipregion-*.apk ./luci-app-ipregion-*.apk ./luci-i18n-ipregion-ru-*.apk
```

Feed checkout example for SDK/buildroot development:

```sh
git clone https://github.com/romanilyin/ipregion-openwrt.git package/ipregion-openwrt
```

Multi-target SDK helper:

```sh
scripts/build-sdk-packages.sh mediatek/filogic
scripts/build-sdk-packages.sh x86/64
scripts/build-sdk-packages.sh ramips/mt7621
scripts/build-sdk-packages.sh ath79/generic
```

The packages are script-only and built as `noarch`, but testing multiple SDK targets catches feed and packaging issues. If the local host lacks OpenWrt SDK prerequisites, install the missing build dependencies first; for local throwaway SDK smoke tests only, `IPREGION_SKIP_PREREQ=1` can bypass SDK prerequisite probing.

## CLI Examples

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
ipregion --output /tmp/run/ipregion/result.json --group primary --ipv4
```

## Check Groups

- `all`: runs every enabled GeoIP, popular service and CDN check.
- `primary` / GeoIP services: query public geolocation APIs and registries to see what country they assign to the router IP.
- `custom` / Popular services: contact major platforms such as Google, YouTube, Twitch, ChatGPT, Netflix and Spotify to see which region, access state or country their web/API endpoints report for this route.
- `cdn` / CDN services: check which CDN edge or region the router reaches, for example Cloudflare, YouTube or Netflix CDN.

GeoIP modes:

- `--geoip-mode lookup`: default; discovers the router egress IP first, then asks GeoIP APIs to look up that IP. This is useful for comparing databases for a concrete address.
- `--geoip-mode route`: asks supported GeoIP APIs what country they see for the request itself. This is useful with split traffic, VPN policies and SOCKS5 routes where the GeoIP API endpoint may be reached through a different path than the generic IP discovery endpoint.

AI provider mode:

- `ipregion ai --json` runs safe unauthenticated endpoint probes for OpenAI, Anthropic, Google Gemini, DeepSeek, Qwen, Kimi, Baidu Qianfan and Zhipu/GLM.
- `401`, `403`, `404`, `405` and `429` can still mean the provider endpoint was reached; the JSON result classifies these separately from DNS, TLS, timeout and network failures.
- API keys are not stored or requested by default.

SOCKS5 DNS modes:

- `--proxy-dns remote` uses `socks5h://`.
- `--proxy-dns local` uses `socks5://`.

## Interface And Proxy Notes

Use `--interface wan` when you need to bind curl to a specific OpenWrt interface name. Interface names are validated before use.

For policy-routing setups such as mwan3, podkop, WARP or another tunnel manager, `curl --interface` is not always equivalent to the route used by client traffic. The most reliable diagnostic target is usually a local SOCKS5 endpoint that already exits through the intended tunnel or policy route.

Result statuses:

- `Denied`: the service rejected access for this route or region.
- `Rate-limit`: the endpoint rate-limited the router IP.
- `N/A`: the check could not produce a meaningful value for this IP family or service.

## LuCI

Menu entries:

- `Status -> IP Region`: run GeoIP/popular/CDN diagnostics and AI endpoint reachability checks, poll background state, view/download JSON.
- `Services -> IP Region`: default UCI settings.

If LuCI shows access denied after manual deploy, restart rpcd:

```sh
/etc/init.d/rpcd restart
```

## CI

GitHub Actions workflows: `.github/workflows/ci.yml` for static checks and `.github/workflows/sdk-build.yml` for manual/tagged SDK package builds.

Local checks:

```sh
scripts/ci/static-checks.sh
scripts/ci/build-ucode.sh /tmp/ipregion-ucode-install
scripts/ci/ucode-checks.sh /tmp/ipregion-ucode-install/bin/ucode
```

The CI builds `ucode` with UCI support from upstream sources and runs `ucode -c` over all backend and rpcd `.uc` files.

## Official OpenWrt Feeds

To appear in the official OpenWrt package lists, the packages need to be accepted into the upstream feeds and then built by OpenWrt buildbots.

- Submit the CLI/backend package to `openwrt/packages`, likely under `net/ipregion`.
- Submit the LuCI app to `openwrt/luci`, likely under `applications/luci-app-ipregion` with `.po` translations.
- Keep builds reproducible and offline; all runtime dependencies must be declared in `DEPENDS` / `LUCI_DEPENDS`.
- Keep `PKG_LICENSE`, SPDX headers, maintainer metadata and source attribution clear.
- Keep the package noarch/script-only unless native code is introduced.
- Add `Signed-off-by` to commits and follow OpenWrt commit style, for example `ipregion: add package` and `luci-app-ipregion: add application`.
- Build-test against current OpenWrt master and the intended stable branch before opening PRs.
- The GitHub self-update button/installer will likely need to be disabled or removed for official feed builds; official packages should update through the OpenWrt package repositories, not by installing untrusted release APKs from GitHub.
- After merge, packages appear in snapshots automatically; stable release availability requires a backport or the next stable release cycle.

## Router Development

Copy `.env.example` to `.env` for local deploy/test helper scripts. Passwords are not stored; `ssh` and `scp` prompt interactively unless `OPENWRT_SSH_KEY` is set.

Default router values:

```sh
OPENWRT_HOST=192.168.2.1
OPENWRT_USER=root
OPENWRT_SSH_PORT=22
```

Helpers:

```sh
scripts/deploy-router.sh
scripts/test-router.sh
```

## Privacy

Diagnostics contact third-party GeoIP, streaming, and CDN endpoints. Those services receive the router's public IP for each check. Debug and runtime logs stay local under `/tmp/run/ipregion/`; this port does not upload logs to public file hosts.

## Attribution

Inspired by and service-compatible with [`vernette/ipregion`](https://github.com/vernette/ipregion), but rewritten as an OpenWrt-native `ucode` backend and LuCI application.

## Routing Scope

The plugin only makes outbound HTTPS requests. It must not add or change firewall, nftables, mwan3, podkop, WARP, or routing rules.
