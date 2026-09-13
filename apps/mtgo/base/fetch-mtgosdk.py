#!/usr/bin/env python3
"""Download the MTGOSDK NuGet packages the bot's NuGet.config expects."""
from __future__ import annotations

import sys
import urllib.request
from pathlib import Path

# Keep in lockstep with mtgo-bot/src/packages.lock.json
VERSION = "1.2.1.20260222"
PACKAGES = ["MTGOSDK", "MTGOSDK.MSBuild", "MTGOSDK.Win32"]
OUTPUT_DIR = Path("/MTGOSDK/packages")
FLAT = "https://api.nuget.org/v3-flatcontainer"


def main() -> int:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for package_id in PACKAGES:
        dest = OUTPUT_DIR / f"{package_id}.{VERSION}.nupkg"
        if dest.exists() and dest.stat().st_size > 0:
            print(f"already have {dest}")
            continue
        lower = package_id.lower()
        url = f"{FLAT}/{lower}/{VERSION}/{lower}.{VERSION}.nupkg"
        print(f"downloading {package_id} {VERSION}")
        try:
            urllib.request.urlretrieve(url, dest)
        except Exception as exc:  # noqa: BLE001
            print(f"failed {package_id}: {exc}", file=sys.stderr)
            return 1
        print(f"saved {dest} ({dest.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
