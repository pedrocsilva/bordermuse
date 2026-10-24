#!/usr/bin/env python3
"""Generate bundled app resources from the shared, typed en-US catalog."""
import argparse
import json
import re
import sys
from pathlib import Path
from string import Formatter

ROOT = Path(__file__).resolve().parents[2]
CATALOG = Path("resources/strings/en-US.json")
OUTPUTS = {
    "macos": Path("apps/macos/BorderMuse/Resources/en-US.lproj/Localizable.strings"),
    "windows": Path("packages/core-dotnet/Resources/en-US.json"),
}


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate catalog field: {key}")
        result[key] = value
    return result


def load_catalog(path):
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object)


def format_text(text, arguments, platform):
    if not isinstance(text, str):
        raise ValueError("Message text must be a string")
    indices = {argument["name"]: (index, argument["type"]) for index, argument in enumerate(arguments)}
    seen = set()
    result = []
    for literal, field, spec, conversion in Formatter().parse(text):
        if arguments:
            literal = literal.replace("%", "%%") if platform == "macos" else literal.replace("{", "{{").replace("}", "}}")
        result.append(literal)
        if field is None:
            continue
        if field not in indices or spec or conversion:
            raise ValueError(f"Unknown or invalid placeholder: {{{field}}}")
        seen.add(field)
        index, kind = indices[field]
        if platform == "macos":
            result.append(f"%{index + 1}$" + ("ld" if kind == "integer" else "@"))
        else:
            result.append("{" + str(index) + (":N0" if kind == "integer" else "") + "}")
    if seen != set(indices):
        raise ValueError("Every declared argument must appear in each platform's text")
    return "".join(result)


def strings_quote(value):
    escapes = {'"': '\\"', "\\": "\\\\", "\n": "\\n", "\r": "\\r", "\t": "\\t"}
    return '"' + "".join(escapes.get(c, f"\\U{ord(c):04X}" if ord(c) < 32 else c) for c in value) + '"'


def render(catalog):
    if not isinstance(catalog, dict) or set(catalog) != {"locale", "strings"} or catalog["locale"] != "en-US":
        raise ValueError("Catalog must contain locale=en-US and strings")
    if not isinstance(catalog["strings"], dict) or not catalog["strings"]:
        raise ValueError("Catalog strings must be a nonempty object")
    values = {platform: {} for platform in OUTPUTS}
    for key, raw in catalog["strings"].items():
        try:
            if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", key):
                raise ValueError("Invalid message key")
            entry = {"text": raw} if isinstance(raw, str) else raw
            if not isinstance(entry, dict) or "text" not in entry or set(entry) - {"text", "arguments", "platforms", "overrides"}:
                raise ValueError("Expected text and optional arguments, platforms or overrides")
            platforms = entry.get("platforms", list(OUTPUTS))
            if not isinstance(platforms, list) or not platforms or any(p not in OUTPUTS for p in platforms) or len(set(platforms)) != len(platforms):
                raise ValueError("Invalid platforms")
            overrides = entry.get("overrides", {})
            if not isinstance(overrides, dict) or set(overrides) - set(platforms):
                raise ValueError("Overrides must target an included platform")
            arguments = entry.get("arguments", [])
            if not isinstance(arguments, list):
                raise ValueError("Arguments must be an ordered list")
            names = set()
            for argument in arguments:
                if not isinstance(argument, dict) or set(argument) != {"name", "type"}:
                    raise ValueError("Arguments require name and type")
                name, kind = argument["name"], argument["type"]
                if not isinstance(name, str) or not name.isidentifier() or name in names or kind not in ("integer", "string"):
                    raise ValueError("Arguments need unique names and integer/string types")
                names.add(name)
            # Validate the common text even when every included platform overrides it.
            format_text(entry["text"], arguments, "macos")
            for platform in platforms:
                values[platform][key] = format_text(overrides.get(platform, entry["text"]), arguments, platform)
        except (ValueError, TypeError) as error:
            raise ValueError(f"{key}: {error}") from error
    macos = "/* Generated from resources/strings/en-US.json. Run python3 scripts/localization/generate.py. */\n"
    macos += "".join(f"{strings_quote(key)} = {strings_quote(value)};\n" for key, value in values["macos"].items())
    return {"macos": macos, "windows": json.dumps(values["windows"], ensure_ascii=False, indent=2) + "\n"}


def generate(root, check=False):
    outputs = render(load_catalog(root / CATALOG))
    stale = []
    for platform, relative in OUTPUTS.items():
        path = root / relative
        if check:
            if not path.is_file() or path.read_text(encoding="utf-8") != outputs[platform]:
                stale.append(relative)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(outputs[platform].encode("utf-8"))
    return stale


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail on stale resources without modifying files")
    args = parser.parse_args()
    try:
        stale = generate(ROOT, args.check)
    except (ValueError, OSError) as error:
        print(f"Localization: {error}", file=sys.stderr)
        return 2
    if stale:
        for path in stale:
            print(f"Outdated generated resource: {path}", file=sys.stderr)
        print("Run python3 scripts/localization/generate.py", file=sys.stderr)
        return 1
    print("Localization resources are current." if args.check else "Generated macOS and Windows localization resources.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
