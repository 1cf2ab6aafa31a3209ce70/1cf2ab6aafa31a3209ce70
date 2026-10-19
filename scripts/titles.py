#!/usr/bin/env python3
"""Load and validate the title manifests at Games/<Target>/title.json.

Each manifest registers one app target: its stable title ID (the save
namespace and catalog titleID), bundle identifier, content package and test
directories. Generation, static checks, the mobile test runner and CI read
titles only from here, so adding or removing a title never edits another one.
"""
import argparse
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
FIELDS = {"schemaVersion", "target", "titleID", "appDisplayName", "bundleIdentifier",
          "contentPackage", "unitTests", "uiTests"}
OPTIONAL = {"restartProof"}


class Title:
    def __init__(self, manifest, values):
        self.manifest = manifest
        self.directory = manifest.parent
        self.target = values["target"]
        self.title_id = values["titleID"]
        self.app_display_name = values["appDisplayName"]
        self.bundle_identifier = values["bundleIdentifier"]
        self.content_package = values["contentPackage"]
        self.content_product = Path(self.content_package).name
        self.content_resources = f"{self.content_package}/Sources/{self.content_product}/Resources"
        self.unit_tests = values["unitTests"]
        self.ui_tests = values["uiTests"]
        self.restart_proof = values.get("restartProof")

    @property
    def source_directory(self):
        return str(self.directory.relative_to(ROOT))

    @property
    def owned_paths(self):
        """Repository paths whose changes affect only this title."""
        return [self.source_directory, self.content_package, self.unit_tests, self.ui_tests]


def _require(condition, message):
    if not condition:
        raise ValueError(message)


def load(root=ROOT):
    titles = []
    for manifest in sorted((root / "Games").glob("*/title.json")):
        relative = manifest.relative_to(root)
        try:
            values = json.loads(manifest.read_text())
        except json.JSONDecodeError as error:
            raise ValueError(f"{relative}: malformed JSON ({error})") from error
        _require(isinstance(values, dict) and FIELDS <= set(values) <= FIELDS | OPTIONAL,
                 f"{relative}: expected fields {sorted(FIELDS)}, optional {sorted(OPTIONAL)}")
        _require(values["schemaVersion"] == 1, f"{relative}: unsupported schemaVersion")
        _require(all(isinstance(values[key], str) for key in FIELDS - {"schemaVersion"}),
                 f"{relative}: fields other than schemaVersion must be strings")
        _require(values["target"] == manifest.parent.name and re.fullmatch(r"[A-Z][A-Za-z0-9]*", values["target"]),
                 f"{relative}: target must be an UpperCamelCase name matching its directory")
        _require(re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", values["titleID"]) and len(values["titleID"]) <= 80,
                 f"{relative}: titleID must be lowercase words joined by hyphens")
        _require(re.fullmatch(r"[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+", values["bundleIdentifier"]),
                 f"{relative}: invalid bundleIdentifier")
        _require(values["appDisplayName"].strip() == values["appDisplayName"] and 0 < len(values["appDisplayName"]) <= 30,
                 f"{relative}: appDisplayName must be 1...30 characters without outer spaces")
        title = Title(manifest, values)
        _require(re.fullmatch(r"Games/[A-Z][A-Za-z0-9]*", title.content_package)
                 and (root / title.content_package / "Package.swift").is_file(),
                 f"{relative}: contentPackage must be a local package directory under Games")
        _require((root / title.content_resources).is_dir(), f"{relative}: missing {title.content_resources}")
        for key, path in [("unitTests", title.unit_tests), ("uiTests", title.ui_tests)]:
            _require(re.fullmatch(r"Tests/[A-Z][A-Za-z0-9]*", path) and (root / path).is_dir(),
                     f"{relative}: {key} must be an existing directory under Tests")
        if title.restart_proof is not None:
            _require(isinstance(title.restart_proof, str)
                     and title.restart_proof.startswith(Path(title.unit_tests).name + "/"),
                     f"{relative}: restartProof must name a test in {title.unit_tests}")
        titles.append(title)
    _require(titles, "No title manifests found under Games/*/title.json")
    for attribute in ["target", "title_id", "bundle_identifier", "content_package", "unit_tests", "ui_tests"]:
        values = [getattr(title, attribute) for title in titles]
        _require(len(values) == len(set(values)), f"Title manifests must not share a {attribute}")
    return titles


# Documentation and the disposable experiments never change a title's build.
UNTESTED = ("roadmap/", "docs/", "experiments/")


def affected(titles, changed_paths):
    """Titles whose tests a change requires: all of them when any shared path changed."""
    selected = set()
    for path in changed_paths:
        if path.endswith(".md") or path == "LICENSE" or path.startswith(UNTESTED):
            continue
        owners = [title for title in titles
                  if any(path == owned or path.startswith(owned + "/") for owned in title.owned_paths)]
        if not owners:
            return [title.target for title in titles]
        selected.update(title.target for title in owners)
    return [title.target for title in titles if title.target in selected]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("targets", help="Print one app target per line")
    commands.add_parser("content-packages", help="Print one title content package per line")
    selection = commands.add_parser("affected", help="Print a JSON list of targets whose tests the changed paths require")
    selection.add_argument("changed", type=argparse.FileType(), help="File with one changed repository path per line")
    args = parser.parse_args()
    try:
        titles = load()
    except ValueError as error:
        print(f"Title manifest error: {error}", file=sys.stderr)
        return 1
    if args.command == "targets":
        print("\n".join(title.target for title in titles))
    elif args.command == "content-packages":
        print("\n".join(title.content_package for title in titles))
    else:
        changed = [line.strip() for line in args.changed if line.strip()]
        print(json.dumps(affected(titles, changed)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
