#!/usr/bin/env python3
"""Validate a title's string catalog against the languages its title.json declares.

For every key in <title>/Localizable.xcstrings and every declared language:
a non-empty value in state "translated" (plural and device variations and
substitutions included), no stale extraction and no needs_review or new
states, and format placeholders that match the source language's. Keys marked
shouldTranslate false need only a source value.

title.json may declare "languages" (a list of BCP 47 codes that includes the
catalog's source language). Without it, only the source language is checked.

--stringsdata names a build-intermediates directory holding the .stringsdata
files Xcode extracts from the app target's Swift code (SWIFT_EMIT_LOC_STRINGS).
A catalog key no code references fails unless marked "extractionState":
"manual". A code key missing from the catalog fails when the title declares a
language besides the source: that text would ship untranslated. With the
source language alone the key falls back to itself and is only counted.

--app names the built bundle: it may ship no .lproj for an undeclared
language, and each declared language must ship one when the catalog has keys.
"""
import argparse
import json
from pathlib import Path
import plistlib
import re
import sys

# Substitutions and %% come first: otherwise `#` reads as a flag and %#@name@ parses as %@.
PLACEHOLDER = re.compile(r"%(?:\d+\$)?#@([A-Za-z0-9_]+)@|%%"
                         r"|%(?:(\d+)\$)?[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(hh|h|ll|l|q|z|t|j|L)?([@dDiuUxXoOfFeEgGcCsSaAp])")
ALLOWED_STATES = {"translated"}


def placeholders(value):
    """Format arguments as (position, conversion); substitutions as ('sub', name). %% is ignored."""
    found, position = set(), 0
    for match in PLACEHOLDER.finditer(value):
        substitution, explicit, length, conversion = match.groups()
        if substitution:
            found.add(("sub", substitution))
        elif conversion:
            position = int(explicit) if explicit else position + 1
            found.add((position, (length or "") + conversion))
    return found


def units(localization, path=""):
    """Every (path, stringUnit) leaf of one language's localization, including substitutions."""
    leaves = []
    if "stringUnit" in localization:
        leaves.append((path or "value", localization["stringUnit"]))
    for kind, variants in localization.get("variations", {}).items():
        for name, variant in variants.items():
            leaves += units(variant, f"{path}{kind}.{name}/")
    for name, substitution in localization.get("substitutions", {}).items():
        leaves += units(substitution, f"{path}substitution {name}/")
    return leaves


def declared_languages(title_dir, catalog):
    manifest = json.loads((title_dir / "title.json").read_text())
    source = catalog.get("sourceLanguage")
    languages = manifest.get("languages")
    if languages is None:
        return [source], "title.json declares no languages; checking the source language only"
    if (not isinstance(languages, list) or not languages or len(set(languages)) != len(languages)
            or not all(isinstance(code, str) and re.fullmatch(r"[a-z]{2,3}(-[A-Za-z0-9]+)*", code) for code in languages)):
        raise ValueError("title.json languages must be a non-empty list of unique BCP 47 codes")
    if source not in languages:
        raise ValueError(f"title.json languages must include the catalog source language {source!r}")
    return languages, f"title.json declares {', '.join(languages)}"


def code_keys(directory):
    paths = sorted(Path(directory).rglob("*.stringsdata"))
    if not paths:
        raise ValueError(f"no .stringsdata files under {directory}; was the app built with SWIFT_EMIT_LOC_STRINGS?")
    keys = set()
    for path in paths:
        data = json.loads(path.read_text())
        for entry in data.get("tables", {}).get("Localizable", []):
            keys.add(entry["key"])
    return keys


def check(title_dir, stringsdata=None, app=None):
    problems, notes = [], []
    catalog = json.loads((title_dir / "Localizable.xcstrings").read_text())
    source = catalog.get("sourceLanguage")
    strings = catalog.get("strings")
    if not isinstance(source, str) or not isinstance(strings, dict):
        return [f"{title_dir.name}: Localizable.xcstrings needs a sourceLanguage and a strings dictionary"], notes
    languages, note = declared_languages(title_dir, catalog)
    notes.append(note)
    for key, entry in sorted(strings.items()):
        label = f"{title_dir.name} {key!r}"
        localizations = entry.get("localizations", {})
        if entry.get("extractionState") == "stale":
            problems.append(f"{label}: stale extraction (no longer in code)")
        source_leaves = units(localizations[source]) if source in localizations else [("value", {"state": "translated", "value": key})]
        source_placeholders = set().union(*(placeholders(unit.get("value", "")) for _, unit in source_leaves))
        wanted = [source] if entry.get("shouldTranslate") is False else languages
        for language in wanted:
            leaves = source_leaves if language == source else units(localizations.get(language, {}))
            if not leaves:
                problems.append(f"{label}: no {language} translation")
                continue
            found = set()
            for path, unit in leaves:
                state, value = unit.get("state"), unit.get("value", "")
                where = f"{label} [{language} {path}]"
                if state not in ALLOWED_STATES:
                    problems.append(f"{where}: state {state!r}, expected translated")
                if not value.strip():
                    problems.append(f"{where}: empty value")
                current = placeholders(value)
                found |= current
                if not current <= source_placeholders:
                    problems.append(f"{where}: placeholders {sorted(map(str, current - source_placeholders))} not in the source")
            if language != source and found != source_placeholders:
                problems.append(f"{label} [{language}]: placeholders {sorted(map(str, found))} differ from source "
                                f"{sorted(map(str, source_placeholders))}")
    if stringsdata is not None:
        referenced = code_keys(stringsdata)
        for key in sorted(set(strings) - referenced):
            if strings[key].get("extractionState") != "manual":
                problems.append(f"{title_dir.name} {key!r}: catalog key no code references (stale; mark it manual if intended)")
        missing = sorted(referenced - set(strings))
        if missing and len(languages) > 1:
            problems += [f"{title_dir.name} {key!r}: code key missing from the catalog ships untranslated" for key in missing]
        elif missing:
            notes.append(f"{len(missing)} code key(s) are not in the catalog and fall back to the {source} key text")
    if app is not None:
        info = plistlib.loads((Path(app) / "Info.plist").read_bytes())
        if info.get("CFBundleDevelopmentRegion", source) != source:
            problems.append(f"{Path(app).name}: CFBundleDevelopmentRegion {info['CFBundleDevelopmentRegion']!r} "
                            f"is not the catalog source language {source!r}")
        shipped = {path.stem for path in Path(app).glob("*.lproj")} - {"Base"}
        for language in sorted(shipped - set(languages)):
            problems.append(f"{Path(app).name}: ships {language}.lproj, which title.json does not declare")
        if strings:
            for language in sorted(set(languages) - shipped):
                problems.append(f"{Path(app).name}: declared language {language} has no {language}.lproj in the bundle")
        notes.append(f"bundle languages: {', '.join(sorted(shipped)) or 'none (empty catalog compiles to no .lproj)'}")
    return problems, notes


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("title", type=Path, help="Title directory holding title.json and Localizable.xcstrings")
    parser.add_argument("--stringsdata", type=Path, help="Build intermediates directory of the app target")
    parser.add_argument("--app", type=Path, help="Built .app bundle of the title")
    args = parser.parse_args()
    try:
        problems, notes = check(args.title.resolve(), args.stringsdata, args.app)
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        problems, notes = [f"{args.title.name}: {error}"], []
    for note in notes:
        print(f"note: {note}")
    if problems:
        print("Localization check failed:\n  " + "\n  ".join(problems), file=sys.stderr)
        return 1
    count = len(json.loads((args.title / "Localizable.xcstrings").read_text())["strings"])
    print(f"Localization check passed for {args.title.name}: {count} catalog key(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
