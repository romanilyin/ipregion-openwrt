#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

import json
import os
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
INSTALLER = ROOT / "install.sh"
ARCH = "aarch64_cortex-a53"


FAKE_WGET = r'''#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

scenario = os.environ["INSTALLER_SCENARIO"]
output = Path(sys.argv[sys.argv.index("-O") + 1])
url = sys.argv[-1]
with Path(os.environ["DOWNLOAD_LOG"]).open("a", encoding="utf-8") as stream:
    stream.write(url + "\n")

if str(output) == "/dev/null":
    raise SystemExit(0)

if "/repos/" in url:
    assets = [
        "ipregion-2026.9.2-r3.apk",
        "luci-app-ipregion-2026.9.2-r3.apk",
        "luci-i18n-ipregion-ru-26.245.53062~2752be0.apk",
    ]
    if scenario == "new":
        assets.append("ipregion-dns-helper-aarch64_cortex-a53-2026.9.2-r3.apk")
    output.write_text(json.dumps({"assets": [
        {"browser_download_url": "https://assets.invalid/" + name} for name in assets
    ]}), encoding="utf-8")
    raise SystemExit(0)

name = url.rsplit("/", 1)[-1]
if name.startswith("ipregion-dns-helper-"):
    if scenario == "missing":
        raise SystemExit(1)
    output.write_text("HELPER", encoding="utf-8")
elif name == "ipregion.apk" or name.startswith("ipregion-2026"):
    output.write_text("OLD" if scenario == "old" else "NEW", encoding="utf-8")
elif name.startswith("luci-app-ipregion") or name.startswith("luci-i18n-ipregion-ru"):
    output.write_text("LUCI", encoding="utf-8")
else:
    raise SystemExit(1)
'''


FAKE_APK = r'''#!/usr/bin/env python3
import os
import sys
from pathlib import Path

if sys.argv[1] == "adbdump":
    marker = Path(sys.argv[2]).read_text(encoding="utf-8")
    print("info:")
    print("  depends:")
    if marker == "NEW":
        print("    - ipregion-dns-helper")
    raise SystemExit(0)
if sys.argv[1] == "add":
    for item in sys.argv[2:]:
        if item.endswith(".apk") and not Path(item).is_file():
            raise SystemExit(2)
    with Path(os.environ["APK_LOG"]).open("a", encoding="utf-8") as stream:
        stream.write(" ".join(sys.argv[1:]) + "\n")
    raise SystemExit(0)
if sys.argv[1] == "update":
    raise SystemExit(0)
raise SystemExit(2)
'''


def write_executable(path, content):
    path.write_text(content, encoding="utf-8")
    path.chmod(0o755)


def run_installer(directory, scenario, package_arch=ARCH):
    fake_bin = directory / "bin"
    fake_bin.mkdir(parents=True)
    write_executable(fake_bin / "wget", FAKE_WGET)
    write_executable(fake_bin / "apk", FAKE_APK)
    write_executable(fake_bin / "id", "#!/bin/sh\n[ \"$1\" = -u ] && { printf '0\\n'; exit 0; }\nexec /usr/bin/id \"$@\"\n")

    download_log = directory / "downloads.log"
    apk_log = directory / "apk.log"
    env = os.environ.copy()
    env.update({
        "PATH": str(fake_bin) + os.pathsep + env["PATH"],
        "TMPDIR": str(directory),
        "INSTALLER_SCENARIO": scenario,
        "DOWNLOAD_LOG": str(download_log),
        "APK_LOG": str(apk_log),
        "IPREGION_PACKAGE_ARCH": package_arch,
        "IPREGION_APK_UPDATE": "0",
        "IPREGION_DOWNLOAD_RETRIES": "1",
        "IPREGION_DOWNLOAD_RETRY_DELAY": "0",
        "IPREGION_GITHUB_API": "https://api.invalid",
        "IPREGION_GITHUB_DOWNLOAD_BASE": "https://assets.invalid",
    })
    result = subprocess.run(["sh", str(INSTALLER)], env=env, text=True,
                            capture_output=True, check=False)
    downloads = download_log.read_text(encoding="utf-8") if download_log.exists() else ""
    apk_calls = apk_log.read_text(encoding="utf-8") if apk_log.exists() else ""
    return result, downloads, apk_calls


with tempfile.TemporaryDirectory(prefix="ipregion-installer-") as tmp:
    base = Path(tmp)

    new_result, new_downloads, new_apk = run_installer(base / "new", "new")
    assert new_result.returncode == 0, new_result.stderr + new_result.stdout
    assert "ipregion-2026.9.2-r3.apk" in new_downloads
    assert f"ipregion-dns-helper-{ARCH}-2026.9.2-r3.apk" in new_downloads
    assert f"ipregion-dns-helper-{ARCH}.apk" in new_apk

    old_result, old_downloads, old_apk = run_installer(base / "old", "old")
    assert old_result.returncode == 0, old_result.stderr + old_result.stdout
    assert "ipregion-dns-helper" not in old_downloads
    assert "ipregion-dns-helper" not in old_apk

    missing_result, _, _ = run_installer(base / "missing", "missing")
    assert missing_result.returncode != 0
    assert "failed to download GitHub release assets" in missing_result.stderr

    no_arch_result, _, _ = run_installer(base / "no-arch", "new", package_arch="")
    assert no_arch_result.returncode != 0
    assert "DISTRIB_ARCH is required" in no_arch_result.stdout

print("installer checks OK")
