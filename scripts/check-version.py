#!/usr/bin/env python3
import json
import os
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
metadata = json.loads((root / "app.json").read_text())
version = metadata["version"]
if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
    raise SystemExit("app.json version must be X.Y.Z")
ref = os.environ.get("GITHUB_REF", "")
if ref.startswith("refs/tags/") and ref != "refs/tags/v" + version:
    raise SystemExit("Release tag must match app.json version")
if (root / "package.json").exists():
    for name in ["package.json", "src-tauri/tauri.conf.json"]:
        if json.loads((root / name).read_text())["version"] != version:
            raise SystemExit(name + " version must match app.json")
    cargo = (root / "src-tauri/Cargo.toml").read_text()
    if re.search(r'^version\s*=\s*"([^"]+)"', cargo, re.M).group(1) != version:
        raise SystemExit("Cargo.toml version must match app.json")
