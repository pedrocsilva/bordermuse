#!/usr/bin/env python3
"""Fetch hash-pinned public QA photos into an ignored output directory."""
import hashlib
import json
import sys
import urllib.request
from pathlib import Path

root = Path(__file__).resolve().parents[2]
output = Path(sys.argv[1])
manifest = json.loads((root / "tests/photo-parity/sources.json").read_text())
inputs = output / "input"
inputs.mkdir(parents=True, exist_ok=True)
for source in manifest["sources"]:
    path = inputs / source["file"]
    if path.exists():
        if hashlib.sha256(path.read_bytes()).hexdigest() != source["sha256"]:
            raise RuntimeError(f"Existing file differs; preserving it: {path}")
        continue
    request = urllib.request.Request(source["url"], headers={"User-Agent": "BorderMuse-QA/0.1 (public photo comparison)"})
    with urllib.request.urlopen(request, timeout=60) as response:
        data = response.read(20 * 1024 * 1024 + 1)
    if len(data) != source["bytes"] or hashlib.sha256(data).hexdigest() != source["sha256"]:
        raise RuntimeError(f"Public source changed: {source['file']}")
    with path.open("xb") as destination:
        destination.write(data)
    print("Verified " + source["file"])
license_path = output / "exif-examples-LICENSE.txt"
if not license_path.exists():
    with urllib.request.urlopen(manifest["mitLicenseUrl"], timeout=60) as response:
        license_text = response.read(65536)
    with license_path.open("xb") as destination:
        destination.write(license_text)
credits = output / "ATTRIBUTION.md"
if not credits.exists():
    credits.write_text("# Public QA sources\n\n" + "\n".join(f"- {s['file']}: {s['credit']} — {s['source']}" for s in manifest["sources"]) + "\n", encoding="utf-8")
