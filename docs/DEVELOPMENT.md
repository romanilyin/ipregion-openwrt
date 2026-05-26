# Development And Packaging Notes

This document collects the technical details that are useful for maintainers, contributors and OpenWrt packaging work. End-user installation and usage are covered in [README.md](../README.md).

## Scope

- Target OpenWrt version: `25.12.4+`.
- Runtime package manager examples use `apk`.
- `ipregion` is a `ucode` CLI/backend package.
- `luci-app-ipregion` is a LuCI app backed by a narrow rpcd/ubus API.
- `luci-i18n-ipregion-ru` provides the Russian LuCI translation.
- Packages are script-only/noarch unless native code is introduced later.

This port intentionally does not wrap the upstream Bash implementation. Runtime dependencies on `bash`, `jq`, `column` and `grep -P` are avoided; OpenWrt runtime dependencies belong in package metadata.

## Local Static Checks

Run from the repository root:

```sh
scripts/ci/static-checks.sh
```

The static checks validate JSON catalogs, rpcd ACL/menu JSON, LuCI gettext coverage, JavaScript syntax and shell syntax.

For local `ucode` syntax checks with UCI support:

```sh
scripts/ci/build-ucode.sh /tmp/ipregion-ucode-install
scripts/ci/ucode-checks.sh /tmp/ipregion-ucode-install/bin/ucode
```

The CI workflow also runs these checks, but GitHub account billing or spending-limit issues can prevent hosted Actions jobs from starting.

## SDK Build Smoke

From an OpenWrt 25.12.4+ buildroot or SDK with this package feed available:

```sh
make package/ipregion/compile V=s
make package/luci-app-ipregion/compile V=s
```

Feed checkout example:

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

The packages are noarch, but testing several SDK targets catches feed, dependency and package metadata issues.

If a local throwaway host lacks OpenWrt SDK prerequisites, `IPREGION_SKIP_PREREQ=1` can bypass SDK prerequisite probing. Do not use that as proof for official package readiness; install the missing SDK host dependencies for real verification.

## Router Smoke Testing

Local helper scripts read optional `.env` and otherwise default to the development router values:

```sh
OPENWRT_HOST=192.168.2.1
OPENWRT_USER=root
OPENWRT_SSH_PORT=22
```

Copy `.env.example` to `.env` for local overrides. Keep `.env` untracked and do not package it into OpenWrt artifacts.

Current router login is password-based; helper scripts let `ssh` and `scp` prompt interactively unless `OPENWRT_SSH_KEY` is set.

Deploy and test helpers:

```sh
scripts/deploy-router.sh
scripts/test-router.sh
```

OpenWrt/dropbear environments may lack an SFTP server, so legacy SCP mode can be required by tooling.

Router smoke checks should cover:

- `ipregion --self-test --json`
- regular GeoIP/popular/CDN runs through CLI and ubus
- `ipregion ai --provider google_gemini --json`
- LuCI page load after `rpcd` restart and `uhttpd` reload
- GeoIP `lookup` and `route` modes
- SOCKS5 local DNS and remote DNS modes when a proxy is available

## Runtime State

Runtime data stays local under `/tmp/run/ipregion/`.

- regular state: `/tmp/run/ipregion/state.json`
- regular result: `/tmp/run/ipregion/result.json`
- regular log: `/tmp/run/ipregion/log.txt`
- AI state: `/tmp/run/ipregion/ai-state.json`
- AI result: `/tmp/run/ipregion/ai-result.json`
- AI log: `/tmp/run/ipregion/ai-log.txt`

Endpoint failures must remain per-service and must not abort the whole run.

## LuCI And rpcd

- The rpcd backend is `luci-app-ipregion/root/usr/share/rpcd/ucode/ipregion.uc`.
- It returns `{ 'luci.ipregion': methods }`.
- Keep ACL ubus object names aligned with that backend object.
- The `detected_country` method only reads the latest local result file and must not start network checks from the settings page.
- Do not grant generic exec access.
- LuCI strings must use `_('...')`.
- Translation sources are `po/templates/ipregion.pot` and `po/ru/ipregion.po`.
- Keep service ids and raw JSON field names untranslated.

## Security And Routing Constraints

- Validate user-controlled `interface`, `proxy` and service/provider ids before they affect commands.
- Do not add firewall, nftables, mwan3, podkop, WARP or routing changes.
- This app is diagnostics-only and only makes outbound HTTPS requests.
- SOCKS5 checks should support local DNS through `socks5://` and remote DNS through `socks5h://`.
- Debug/log output must stay local under `/tmp/run/ipregion/`.

## Release Packaging

The public GitHub Release installer is `install.sh` at the repository root.

- It reads GitHub Release metadata.
- It downloads `ipregion*.apk`, `luci-app-ipregion*.apk` and `luci-i18n-ipregion-ru*.apk`.
- It installs with `apk` and `--allow-untrusted` by default because GitHub Release APKs are not from the official OpenWrt package repository.
- It supports `IPREGION_RELEASE`, `IPREGION_INSTALL_LUCI`, `IPREGION_APK_UPDATE`, `IPREGION_REPO`, `IPREGION_GITHUB_API` and `IPREGION_APK_FLAGS`.
- The LuCI update button is kept for public GitHub Release builds and is guarded against downgrades when the installed package is newer than the latest GitHub release.

Before publishing a release:

- run `scripts/ci/static-checks.sh`
- run `scripts/ci/ucode-checks.sh` with a local `ucode` build
- build packages in an OpenWrt SDK
- run focused router smoke tests
- verify LuCI after hard refresh and `rpcd` restart

## Official OpenWrt Feeds

Official OpenWrt feed submission is intentionally not being done right now.

The main blocker is update/install behavior: official packages should update through OpenWrt package repositories, not by installing untrusted APK files from GitHub Releases. Before an upstream feed PR, the GitHub self-update button and installer integration should be disabled, removed or made clearly external to official feed builds.

When preparing official feed work later:

- Submit the CLI/backend package to `openwrt/packages`, likely under `net/ipregion`.
- Submit the LuCI app to `openwrt/luci`, likely under `applications/luci-app-ipregion`, with `.po` translations.
- Keep builds reproducible and offline; all runtime dependencies must be declared in `DEPENDS` or `LUCI_DEPENDS`.
- Keep `PKG_LICENSE`, SPDX headers, maintainer metadata and source attribution clear.
- Keep packages noarch/script-only unless native code is introduced.
- Add `Signed-off-by` to commits.
- Follow OpenWrt commit style, for example `ipregion: add package` and `luci-app-ipregion: add application`.
- Build-test against current OpenWrt master and the intended stable branch before opening PRs.
- After merge, packages appear in snapshots automatically; stable release availability requires a backport or the next stable release cycle.

## Attribution Notes

`vernette/ipregion` is the upstream behavior reference for service intent and compatibility. Do not port its Bash implementation directly.
