<p align="center">
  <img src="luci-app-ipregion/htdocs/luci-static/resources/ipregion/logo.png" width="128" height="128" alt="IPRegion for OpenWrt logo">
</p>

# IPRegion for OpenWrt

[![CI](https://github.com/romanilyin/ipregion-openwrt/actions/workflows/ci.yml/badge.svg)](https://github.com/romanilyin/ipregion-openwrt/actions/workflows/ci.yml)

IPRegion is an OpenWrt CLI and LuCI app for checking how GeoIP APIs, popular services, CDN endpoints and AI providers see your router route, interface or SOCKS5 proxy.

Validated runtime target: OpenWrt 25.12.1+. OpenWrt 24.10.* preparation is experimental on the 24.10 branch and must be verified on real hardware before a public release.

## Documentation

- English: this README.
- Russian: [docs/README.ru.md](docs/README.ru.md).
- Developer and packaging notes: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).
- Developer notes in Russian: [docs/DEVELOPMENT.ru.md](docs/DEVELOPMENT.ru.md).

## What It Does

IPRegion runs diagnostics from the router itself and compares independent service results in one UI and JSON output.

- GeoIP checks show what country public geolocation APIs assign to the route.
- Popular service checks show region, access, rate-limit or denial signals from major platforms.
- CDN checks show which CDN edge or region the router reaches.
- AI checks probe real AI API endpoint domains in safe unauthenticated mode.
- Checks can use the default route, a selected OpenWrt interface or a SOCKS5 proxy.

Packages:

- `ipregion`: CLI/backend diagnostics implemented in `ucode`.
- `luci-app-ipregion`: LuCI UI under `Status -> IP Region`.
- `luci-i18n-ipregion-ru`: Russian LuCI translation.

The release APK packages are `noarch`, so the same assets are intended for supported OpenWrt targets across CPU architectures. Public releases remain validated for OpenWrt 25.12.1+ until 24.10 router smoke testing passes.

## Screenshots

<table>
  <tr>
    <td width="50%"><img src="docs/screens/ru/screen_main_25_12_4.png" alt="IPRegion LuCI status overview"></td>
    <td width="50%"><img src="docs/screens/ru/screen_geoip_direct_25_12_4.png" alt="GeoIP direct check results"></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/screens/ru/screen_services_route_25_12_4.png" alt="Popular service route checks"></td>
    <td width="50%"><img src="docs/screens/ru/screen_cdn_route_25_12_4.png" alt="CDN route checks"></td>
  </tr>
  <tr>
    <td colspan="2"><img src="docs/screens/ru/screen_ai_25_12_2.jpg" alt="AI provider checks"></td>
  </tr>
</table>

## Install

Run on the router:

```sh
wget -qO- https://raw.githubusercontent.com/romanilyin/ipregion-openwrt/main/install.sh | sh
```

The installer downloads `ipregion*.apk`, `luci-app-ipregion*.apk` and `luci-i18n-ipregion-ru*.apk` from the latest GitHub Release and installs them with `apk`.

Options:

- `IPREGION_RELEASE=2026.5.26-6`: install a specific GitHub release tag instead of `latest`.
- `IPREGION_INSTALL_LUCI=0`: install only the CLI/backend package.
- `IPREGION_APK_UPDATE=0`: skip `apk update` before installation.
- `IPREGION_DOWNLOAD_RETRIES=5`: retry GitHub metadata and APK downloads more times.

Pinned release example:

```sh
wget -qO- https://raw.githubusercontent.com/romanilyin/ipregion-openwrt/main/install.sh | IPREGION_RELEASE=2026.5.26-6 sh
```

Manual install from downloaded APK files:

```sh
apk add --allow-untrusted ./ipregion-*.apk ./luci-app-ipregion-*.apk ./luci-i18n-ipregion-ru-*.apk
```

## LuCI

Open `Status -> IP Region` in LuCI.

- Run GeoIP, popular service, CDN and AI endpoint checks from one page.
- Choose IP mode, interface, SOCKS5 proxy, timeout and GeoIP mode.
- Configure the saved SOCKS5 proxy in `Services -> IP Region`, then select it on the Status page.
- Set a reference country to highlight matching country values in orange and different country values in blue.
- AI checks show separate IPv4 and IPv6 provider rows when `IPv4 and IPv6` mode is selected; unavailable transports are shown explicitly.
- View progress while checks run.
- Download JSON results. JSON downloads include raw IP addresses.
- Update the package from GitHub Releases through the version card; downgrade protection prevents installing an older latest release.
- Open `Services -> IP Region` for default UCI settings.

## CLI Examples

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
```

## Check Modes

- `--group all`: run every enabled GeoIP, popular service and CDN check.
- `--group primary`: GeoIP services.
- `--group custom`: popular services.
- `--group cdn`: CDN services.
- `--geoip-mode lookup`: discover the router egress IP first, then ask GeoIP APIs to look up that IP.
- `--geoip-mode route`: ask supported GeoIP APIs what country they see for the request itself.
- `ipregion ai --json`: run safe AI provider endpoint probes without storing or requesting API keys.
- `ipregion ai --ip-mode both --json`: run each selected AI provider through separate IPv4 and IPv6 probes.

For SOCKS5 proxy checks:

- `--proxy-dns remote` uses `socks5h://`.
- `--proxy-dns local` uses `socks5://`.

## Notes

- `401`, `403`, `404`, `405` and `429` in AI mode can still mean that the provider endpoint was reached; DNS, TLS, timeout and network failures are classified separately.
- With domain-based split routing, a generic egress IP check can differ from the route used by a specific service or AI endpoint domain.
- For policy-routing setups, a local SOCKS5 endpoint that already exits through the intended tunnel is usually the most reliable diagnostic target.

## Privacy And Scope

Diagnostics contact third-party GeoIP, streaming, CDN and AI endpoints. Those services receive the router's public IP for each check.

Runtime state, results and logs stay local under `/tmp/run/ipregion/`.

IPRegion is diagnostics-only. It does not add or change firewall, nftables, mwan3, podkop, WARP or routing rules.

## Attribution

Inspired by and service-compatible with [`vernette/ipregion`](https://github.com/vernette/ipregion), but rewritten as an OpenWrt-native `ucode` backend and LuCI application.
