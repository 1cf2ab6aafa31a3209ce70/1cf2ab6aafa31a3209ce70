#!/usr/bin/env python3
"""Prove check-localization.py passes a complete catalog and refuses each seeded defect.

Writes fixture title directories (title.json and Localizable.xcstrings),
extracted-strings files and app bundles to a temporary directory. The clean
catalog covers plain strings, plural variations, a plural substitution, a
%i placeholder, a positional placeholder reordering and an untranslatable key
in English and German.
"""
import copy
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

SCRIPT = Path(__file__).resolve().with_name("check-localization.py")


def unit(value, state="translated"):
    return {"stringUnit": {"state": state, "value": value}}


def boards(one, other):
    return {"boards": {"argNum": 1, "formatSpecifier": "lld",
                       "variations": {"plural": {"one": unit(one), "other": unit(other)}}}}


CLEAN = {
    "sourceLanguage": "en",
    "version": "1.0",
    "strings": {
        "Score: %lld": {"localizations": {"en": unit("Score: %lld"), "de": unit("Punkte: %lld")}},
        "Row %lld, column %lld": {"localizations": {"de": unit("Spalte %2$lld, Zeile %1$lld")}},
        "%lld blocks left": {"localizations": {
            "en": {"variations": {"plural": {"one": unit("One block left"), "other": unit("%lld blocks left")}}},
            "de": {"variations": {"plural": {"one": unit("Ein Block übrig"), "other": unit("%lld Blöcke übrig")}}}}},
        "%lld boards cleared": {"localizations": {
            "en": dict(unit("%#@boards@ cleared"), substitutions=boards("%arg board", "%arg boards")),
            "de": dict(unit("%#@boards@ geschafft"), substitutions=boards("%arg Brett", "%arg Bretter"))}},
        "Moves: %i": {"localizations": {"de": unit("Züge: %i")}},
        "Block Match": {"shouldTranslate": False},
        "Play": {"extractionState": "manual", "localizations": {"de": unit("Spielen")}},
    },
}
CODE_KEYS = ["Score: %lld", "Row %lld, column %lld", "%lld blocks left", "%lld boards cleared", "Moves: %i", "Block Match"]


def title(root, name, catalog, languages=("en", "de"), keys=CODE_KEYS, lproj=("en", "de")):
    directory = root / name / "FixtureTitle"
    directory.mkdir(parents=True)
    manifest = {"schemaVersion": 1, "target": "FixtureTitle"}
    if languages is not None:
        manifest["languages"] = list(languages)
    (directory / "title.json").write_text(json.dumps(manifest))
    (directory / "Localizable.xcstrings").write_text(json.dumps(catalog))
    intermediates = root / name / "intermediates"
    intermediates.mkdir()
    (intermediates / "Fixture.stringsdata").write_text(json.dumps(
        {"source": "Fixture.swift", "tables": {"Localizable": [{"comment": "", "key": key} for key in keys]}, "version": 1}))
    app = root / name / "FixtureTitle.app"
    app.mkdir()
    (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleDevelopmentRegion": "en"}))
    for language in lproj:
        (app / f"{language}.lproj").mkdir()
    return directory, intermediates, app


def run(paths):
    directory, intermediates, app = paths
    result = subprocess.run([sys.executable, str(SCRIPT), str(directory), "--stringsdata", str(intermediates),
                             "--app", str(app)], capture_output=True, text=True)
    return result.returncode, result.stderr


def mutate(change):
    catalog = copy.deepcopy(CLEAN)
    change(catalog["strings"])
    return catalog


def main():
    cases = [
        ("missing translation", mutate(lambda s: s["Score: %lld"]["localizations"].pop("de")), {}, "no de translation"),
        ("empty value", mutate(lambda s: s["Score: %lld"]["localizations"]["de"].update(unit("  "))), {}, "empty value"),
        ("needs review", mutate(lambda s: s["Score: %lld"]["localizations"]["de"].update(unit("Punkte: %lld", "needs_review"))),
         {}, "state 'needs_review'"),
        ("stale key", mutate(lambda s: s["Score: %lld"].update(extractionState="stale")), {}, "stale extraction"),
        ("placeholder type", mutate(lambda s: s["Score: %lld"]["localizations"]["de"].update(unit("Punkte: %@"))), {},
         "not in the source"),
        ("dropped placeholder", mutate(lambda s: s["Row %lld, column %lld"]["localizations"]["de"].update(unit("Zeile %lld"))),
         {}, "differ from source"),
        ("missing plural", mutate(lambda s: s["%lld blocks left"]["localizations"]["de"]["variations"]["plural"].pop("other")),
         {}, "differ from source"),
        # %#@boards@ must not read as %@ with a # flag, or this replacement would match the source.
        ("substitution replaced by %@", mutate(lambda s: s["%lld boards cleared"]["localizations"]["de"]["stringUnit"]
                                               .update(value="%@ geschafft")), {}, "not in the source"),
        ("dropped %i placeholder", mutate(lambda s: s["Moves: %i"]["localizations"]["de"].update(unit("Züge"))),
         {}, "differ from source"),
        ("code key not in catalog", CLEAN, {"keys": CODE_KEYS + ["Pause"]}, "'Pause': code key missing from the catalog"),
        ("catalog key not in code", CLEAN, {"keys": CODE_KEYS[1:]}, "'Score: %lld': catalog key no code references"),
        ("undeclared bundle language", CLEAN, {"lproj": ("en", "de", "fr")}, "ships fr.lproj"),
        ("declared language not shipped", CLEAN, {"lproj": ("en",)}, "declared language de has no de.lproj"),
        ("languages without source", CLEAN, {"languages": ("de",)}, "must include the catalog source language"),
    ]
    with tempfile.TemporaryDirectory(prefix="gamecore-localization-") as temporary:
        root = Path(temporary)
        code, errors = run(title(root, "clean", CLEAN))
        assert code == 0, ("clean", errors)
        print("PASS clean en+de catalog: exit 0")
        # The real titles today: no declared languages and an empty catalog.
        code, errors = run(title(root, "source-only", {"sourceLanguage": "en", "strings": {}, "version": "1.0"},
                                 languages=None, lproj=()))
        assert code == 0, ("source only", errors)
        print("PASS source-only title with code keys outside the catalog: exit 0")
        for index, (name, catalog, options, fragment) in enumerate(cases):
            code, errors = run(title(root, f"case-{index}", catalog, **options))
            assert code == 1 and fragment in errors, (name, code, errors)
            print(f"PASS {name}: refused")
    print("Localization check passes a complete catalog and refuses every seeded defect")


if __name__ == "__main__":
    main()
