#!/usr/bin/env python3
"""Create a skeletal title that builds and passes its tests before any gameplay.

Copies scripts/title-template with the title's names, renders a placeholder
app icon and regenerates the Xcode project. The new title registers through
module contract version 1 and links only the shared packages and its own
content; no core source file is copied.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = Path(__file__).resolve().parent / "title-template"
GAME_TYPES = ["block", "tile", "unscrew", "dig"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", help="UpperCamelCase app target, for example TileTitle")
    parser.add_argument("--title-id", required=True, help="Stable save namespace and catalog ID, for example tile-match")
    parser.add_argument("--display-name", required=True, help="Name under the app icon, at most 30 characters")
    parser.add_argument("--game-type", required=True, choices=GAME_TYPES, help="GameCore level type for the catalog")
    parser.add_argument("--content", help="Content package name (default: the target with Title replaced by Content)")
    parser.add_argument("--bundle-id", help="Bundle identifier (default: local.gamecore.<target>)")
    args = parser.parse_args()
    content = args.content or (args.target[:-5] + "Content" if args.target.endswith("Title") else args.target + "Content")
    names = {
        "__TARGET__": args.target,
        "__CONTENT__": content,
        "__TITLE_ID__": args.title_id,
        "__DISPLAY_NAME__": args.display_name,
        "__BUNDLE_ID__": args.bundle_id or f"local.gamecore.{args.target}",
        "__GAME_TYPE__": args.game_type,
    }
    if not re.fullmatch(r"[A-Z][A-Za-z0-9]*", args.target) or not re.fullmatch(r"[A-Z][A-Za-z0-9]*", content):
        parser.error("target and content names must be UpperCamelCase letters and digits")
    if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", args.title_id):
        parser.error("--title-id must be lowercase words joined by hyphens")
    if not 0 < len(args.display_name) <= 30 or '"' in args.display_name or "\\" in args.display_name:
        parser.error("--display-name must be 1...30 characters without quotes or backslashes")
    destinations = {}
    for source in sorted(TEMPLATE.rglob("*")):
        if source.is_dir() or source.name == ".DS_Store":
            continue
        relative = str(source.relative_to(TEMPLATE))
        for placeholder, value in names.items():
            relative = relative.replace(placeholder, value)
        destinations[source] = ROOT / relative
    owned = [f"Games/{args.target}", f"Games/{content}", f"Tests/{args.target}Tests", f"Tests/{args.target}UITests"]
    existing = [path for path in owned if (ROOT / path).exists()]
    if existing:
        raise SystemExit(f"Refusing to overwrite existing paths: {', '.join(existing)}")
    for source, destination in destinations.items():
        destination.parent.mkdir(parents=True, exist_ok=True)
        if source.suffix in {".png", ".txt"}:
            destination.write_bytes(source.read_bytes())
            continue
        text = source.read_text()
        for placeholder, value in names.items():
            # Validated names need no escaping in the JSON, plist and Swift templates.
            text = text.replace(placeholder, value)
        destination.write_text(text)
    icon = ROOT / "Games" / args.target / "Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    subprocess.run([sys.executable, str(ROOT / "scripts/app-icon.py"), str(icon), "--frames", args.title_id], check=True)
    subprocess.run([sys.executable, str(ROOT / "scripts/generate-project.py")], check=True)
    manifest = json.loads((ROOT / "Games" / args.target / "title.json").read_text())
    print(f"Created {args.target} ({manifest['titleID']}) with content package {manifest['contentPackage']}.")
    print("Next: bash scripts/verify.sh, then bash scripts/test-mobile.sh --title " + args.target)


if __name__ == "__main__":
    main()
