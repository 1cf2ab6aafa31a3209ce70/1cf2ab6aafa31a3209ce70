#!/usr/bin/env python3
"""Prove check-asset-provenance.py traces a recorded bundle and refuses each seeded gap.

Builds a fixture repository root (docs/asset-provenance.md, a title with
CONTENT.md and an app icon, and a content package) and a matching app bundle
in a temporary directory, then removes or weakens one record at a time.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

SCRIPT = Path(__file__).resolve().with_name("check-asset-provenance.py")
CONTENT = """# Content record: fixture

- Local paths: the [fixture resources](../FixtureContent/Sources/FixtureContent/Resources) and the [app icon](Assets.xcassets/AppIcon.appiconset).
- Rights: project-authored material is MIT. The bundle carries the [SplitMix64 notice](../FixtureContent/Sources/FixtureContent/Resources/SplitMix64-NOTICE.txt) for the public-domain algorithm; no attribution is required and the notice is retained.
"""
PROVENANCE = "# Content provenance\n\nThe repository's [MIT license](../LICENSE) covers project-authored material.\n"
RESOURCES = {"Resources/catalog.json": "{}", "Resources/Levels/one.json": "{}", "Resources/SplitMix64-NOTICE.txt": "Public domain."}
GENERATED = ["Info.plist", "PkgInfo", "Assets.car", "AppIcon60x60@2x.png", "FixtureContent_FixtureContent.bundle/Info.plist",
             "PrivacyInfo.xcprivacy"]


def fixture(root, content=CONTENT, provenance=PROVENANCE, extra_source=None, extra_packaged=None):
    (root / "docs").mkdir(parents=True)
    (root / "docs" / "asset-provenance.md").write_text(provenance)
    (root / "LICENSE").write_text("MIT")
    title = root / "Games" / "FixtureTitle"
    (title / "Assets.xcassets" / "AppIcon.appiconset").mkdir(parents=True)
    (title / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png").write_bytes(b"\x89PNG")
    (title / "title.json").write_text('{"target": "FixtureTitle", "contentPackage": "Games/FixtureContent"}')
    (title / "CONTENT.md").write_text(content)
    (title / "PrivacyInfo.xcprivacy").write_text("<plist/>")
    sources = root / "Games" / "FixtureContent" / "Sources" / "FixtureContent"
    app = root / "build" / "FixtureTitle.app"
    (app / "FixtureContent_FixtureContent.bundle").mkdir(parents=True)
    (app / "FixtureTitle").write_bytes(b"\xcf\xfa\xed\xfe")
    for name in GENERATED:
        (app / name).write_text("generated")
    files = dict(RESOURCES)
    files.update(extra_source or {})
    for relative, text in files.items():
        (sources / relative).parent.mkdir(parents=True, exist_ok=True)
        (sources / relative).write_text(text)
        packaged = app / "FixtureContent_FixtureContent.bundle" / relative
        packaged.parent.mkdir(parents=True, exist_ok=True)
        packaged.write_text(text)
    for relative, text in (extra_packaged or {}).items():
        (app / relative).parent.mkdir(parents=True, exist_ok=True)
        (app / relative).write_text(text)
    return app


def run(root, app):
    result = subprocess.run([sys.executable, str(SCRIPT), "--root", str(root), str(app)], capture_output=True, text=True)
    return result.returncode, result.stderr


def main():
    resources_link = "the [fixture resources](../FixtureContent/Sources/FixtureContent/Resources)"
    catalog_only = "the [catalog](../FixtureContent/Sources/FixtureContent/Resources/catalog.json)"
    one_file = "the [catalog](../FixtureContent/Sources/FixtureContent/Resources/catalog.json), [levels](../FixtureContent/Sources/FixtureContent/Resources/Levels)"
    cases = [
        ("unrecorded packaged file", {"content": CONTENT.replace(resources_link, catalog_only)},
         "Resources/Levels/one.json: no provenance record links"),
        ("unrecorded new resource", {"content": CONTENT.replace(resources_link, one_file),
                                     "extra_source": {"Resources/sound.caf": "x"}},
         "Resources/sound.caf: no provenance record links"),
        ("notice without license", {"content": CONTENT.replace(" for the public-domain algorithm", "")},
         "SplitMix64-NOTICE.txt: third-party material"),
        ("upstream asset without license", {"content": CONTENT + "- Sound: the [chime](../FixtureContent/Sources/FixtureContent/Resources/chime.caf) is adapted from an upstream pack.\n",
                                            "extra_source": {"Resources/chime.caf": "x"}},
         "Resources/chime.caf: third-party material"),
        ("packaged file without source", {"extra_packaged": {"Vendor.png": "x"}}, "Vendor.png: packaged file has no repository source"),
        ("unrecorded app icon", {"content": CONTENT.replace(" and the [app icon](Assets.xcassets/AppIcon.appiconset)", "")},
         "AppIcon.png: no provenance record links"),
        ("missing CONTENT.md", {"content": None}, "missing CONTENT.md"),
    ]
    with tempfile.TemporaryDirectory(prefix="gamecore-provenance-") as temporary:
        base = Path(temporary)
        root = base / "clean"
        code, errors = run(root, fixture(root))
        assert code == 0, ("clean", errors)
        print("PASS clean bundle: every packaged file traced, exit 0")
        root = base / "docs-record"
        app = fixture(root, content=CONTENT.replace(" and the [app icon](Assets.xcassets/AppIcon.appiconset)", ""),
                      provenance=PROVENANCE + "\nThe [fixture icon](../Games/FixtureTitle/Assets.xcassets) is original.\n")
        code, errors = run(root, app)
        assert code == 0, ("record in docs/asset-provenance.md", errors)
        print("PASS record in docs/asset-provenance.md: exit 0")
        for index, (name, options, fragment) in enumerate(cases):
            root = base / f"case-{index}"
            content = options.pop("content", CONTENT)
            app = fixture(root, content=content or "", **options)
            if content is None:
                (root / "Games" / "FixtureTitle" / "CONTENT.md").unlink()
            code, errors = run(root, app)
            assert code == 1 and fragment in errors, (name, code, errors)
            print(f"PASS {name}: refused")
    print("Asset provenance check traces every packaged file and refuses each seeded gap")


if __name__ == "__main__":
    main()
