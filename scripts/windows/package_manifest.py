#!/usr/bin/env python3
"""Record and verify the contents of a self-contained Windows development build."""
import argparse
import hashlib
import json
import re
import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = "BorderMuse-build.json"
CHECKSUMS = "SHA256SUMS.txt"
REQUIRED = (
    "BorderMuse.exe", "BorderMuse.dll", "BorderMuse.runtimeconfig.json", "coreclr.dll",
    "Microsoft.UI.Xaml.dll", "BorderMuse.pri", "Microsoft.UI.Xaml.Controls.pri",
    "Assets/AppIcon.ico", "Legal/LICENSE", "Legal/WindowsAppSDK/license.txt",
    "Legal/WindowsAppSDK/NOTICE.txt", "Legal/dotnet/LICENSE.txt", "Legal/dotnet/THIRD-PARTY-NOTICES.TXT",
)


def digest(path):
    sha = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            sha.update(chunk)
    return sha.hexdigest()


def architecture(path):
    with path.open("rb") as source:
        header = source.read(64)
        if len(header) != 64 or header[:2] != b"MZ":
            raise ValueError("Invalid Windows executable header")
        source.seek(struct.unpack_from("<I", header, 60)[0])
        pe = source.read(6)
    if len(pe) != 6 or pe[:4] != b"PE\0\0":
        raise ValueError("Invalid PE header")
    machine = struct.unpack_from("<H", pe, 4)[0]
    if machine not in (0x8664, 0xAA64):
        raise ValueError("Unsupported executable architecture")
    return "x64" if machine == 0x8664 else "arm64"


def generate(folder, commit):
    if not re.fullmatch(r"[0-9a-fA-F]{40}", commit or ""):
        raise ValueError("Provide the full source commit SHA")
    for name in REQUIRED:
        path = folder / name
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError("Missing package component: " + name)
    if (folder / MANIFEST).exists() or (folder / CHECKSUMS).exists():
        raise ValueError("Build metadata already exists; preserving it. Use a fresh publish folder.")
    runtime = json.loads((folder / "BorderMuse.runtimeconfig.json").read_text())["runtimeOptions"]
    if runtime.get("framework") or runtime.get("frameworks") or not runtime.get("includedFrameworks"):
        raise ValueError("The development package must include its .NET runtimes")
    project = ET.parse(ROOT / "apps/windows/BorderMuse.Windows.csproj").getroot()
    metadata = {
        "schemaVersion": 1, "product": "Border Muse", "kind": "unsigned-development",
        "sourceCommit": commit.lower(), "architecture": architecture(folder / "BorderMuse.exe"),
        "version": project.findtext("./PropertyGroup/Version"),
        "fileVersion": project.findtext("./PropertyGroup/FileVersion"),
        "frameworks": runtime["includedFrameworks"],
    }
    with (folder / MANIFEST).open("xb") as output:
        output.write((json.dumps(metadata, indent=2) + "\n").encode("utf-8"))
    files = sorted(path for path in folder.rglob("*") if path.is_file())
    lines = []
    for path in files:
        if not path.resolve().is_relative_to(folder.resolve()):
            raise ValueError("Package files must remain inside the publish folder")
        lines.append(digest(path) + "  " + path.relative_to(folder).as_posix())
    with (folder / CHECKSUMS).open("xb") as output:
        output.write(("\n".join(lines) + "\n").encode("utf-8"))
    verify(folder)
    return metadata


def verify(folder):
    count = 0
    seen = set()
    for line in (folder / CHECKSUMS).read_text(encoding="utf-8").splitlines():
        expected, relative = line.split("  ", 1)
        if relative.casefold() in seen:
            raise ValueError("Duplicate checksum entry")
        seen.add(relative.casefold())
        path = folder / relative
        if not path.resolve().is_relative_to(folder.resolve()) or not re.fullmatch(r"[0-9a-f]{64}", expected):
            raise ValueError("Invalid checksum entry")
        if not path.is_file() or digest(path) != expected:
            raise ValueError("Package checksum mismatch: " + relative)
        count += 1
    if not {name.casefold() for name in REQUIRED + (MANIFEST,)}.issubset(seen):
        raise ValueError("Incomplete package checksums")
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--commit")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    try:
        if args.verify:
            print(f"Verified {verify(args.folder)} package files.")
        else:
            print(json.dumps(generate(args.folder, args.commit), indent=2))
    except (ValueError, OSError, KeyError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
