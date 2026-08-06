#!/usr/bin/env python3
"""Structural checks for the hand-written Xcode project.

CarDash.xcodeproj/project.pbxproj is authored by hand on a machine with no macOS and no
Xcode, so the usual safety net — opening the project and watching it work — does not
exist. Getting a broken project file diagnosed normally means waiting for a macOS runner
to queue, build, and fail with a message that may not name the actual problem.

This script catches the mistakes that are actually plausible when writing a pbxproj by
hand (a typo'd object ID, a build setting pointing at a file that was renamed, a scheme
referencing a target that no longer exists) in about a second, on free Linux minutes.

It is not a substitute for the macOS build. It is a fast filter in front of it.

Run from anywhere:  python3 apps/CarDash/Scripts/validate_project.py
"""

from __future__ import annotations

import plistlib
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

APP_DIR = Path(__file__).resolve().parent.parent
PROJECT = APP_DIR / "CarDash.xcodeproj" / "project.pbxproj"
SCHEME = APP_DIR / "CarDash.xcodeproj" / "xcshareddata" / "xcschemes" / "CarDash.xcscheme"

# Mirrors AppTests/InfoPlistTests.swift. Duplicated on purpose: that suite only runs on
# a macOS runner, and a missing usage string is a crash on a physical device — the one
# environment neither CI job can reach. Catching it here costs nothing.
REQUIRED_INFO_KEYS = [
    "NSLocationWhenInUseUsageDescription",
    "NSAppleMusicUsageDescription",
    "NSMotionUsageDescription",
    "UIBackgroundModes",
    "UISupportedInterfaceOrientations",
    "LSApplicationQueriesSchemes",
    "CFBundleURLTypes",
]

# Build settings whose values are paths relative to the project directory. A rename that
# forgets one of these produces a confusing signing or packaging error on macOS.
PATH_SETTINGS = ["INFOPLIST_FILE", "CODE_SIGN_ENTITLEMENTS"]

errors: list[str] = []


def fail(message: str) -> None:
    errors.append(message)


def check_object_graph(objects: dict, root: str) -> None:
    ids = set(objects)
    if root not in ids:
        fail(f"rootObject {root} is not in objects")

    # Any 24-character CD-prefixed string anywhere in the file is an object reference.
    def walk(value, path: str) -> None:
        if isinstance(value, str):
            if value.startswith("CD") and len(value) == 24 and value not in ids:
                fail(f"dangling object reference {value} at {path}")
        elif isinstance(value, list):
            for index, item in enumerate(value):
                walk(item, f"{path}[{index}]")
        elif isinstance(value, dict):
            for key, item in value.items():
                walk(item, f"{path}.{key}")

    walk(objects, "objects")

    for obj_id, obj in objects.items():
        if "isa" not in obj:
            fail(f"object {obj_id} has no isa")

    orphans = ids - _reachable(objects, root) - {root}
    if orphans:
        names = ", ".join(f"{o} ({objects[o].get('isa', '?')})" for o in sorted(orphans))
        fail(f"objects unreachable from rootObject: {names}")


def _reachable(objects: dict, root: str) -> set[str]:
    seen: set[str] = set()
    stack = [root]
    while stack:
        current = stack.pop()
        if current in seen or current not in objects:
            continue
        seen.add(current)

        def collect(value) -> None:
            if isinstance(value, str):
                if value.startswith("CD") and len(value) == 24 and value in objects:
                    stack.append(value)
            elif isinstance(value, list):
                for item in value:
                    collect(item)
            elif isinstance(value, dict):
                for item in value.values():
                    collect(item)

        collect(objects[current])
    return seen


def check_targets(objects: dict) -> tuple[dict, list[str]]:
    targets = {
        obj_id: obj for obj_id, obj in objects.items() if obj.get("isa") == "PBXNativeTarget"
    }
    if not targets:
        fail("no PBXNativeTarget found")

    names = []
    for obj_id, target in targets.items():
        names.append(target.get("name", "?"))

        # Buildable folders are the whole reason this project file stays small. If a
        # target loses its synchronized group it will still build — with zero source
        # files — which is a maddening failure to diagnose.
        groups = target.get("fileSystemSynchronizedGroups", [])
        if not groups:
            fail(f"target {target.get('name')} has no fileSystemSynchronizedGroups")
        for group_id in groups:
            group = objects.get(group_id, {})
            if group.get("isa") != "PBXFileSystemSynchronizedRootGroup":
                fail(f"target {target.get('name')} references non-synchronized group {group_id}")
                continue
            folder = APP_DIR / group["path"]
            if not folder.is_dir():
                fail(f"buildable folder {group['path']} does not exist on disk")
            elif not any(folder.rglob("*.swift")):
                fail(f"buildable folder {group['path']} contains no Swift sources")

    return targets, names


def check_build_settings(objects: dict) -> None:
    for obj_id, obj in objects.items():
        if obj.get("isa") != "XCBuildConfiguration":
            continue
        settings = obj.get("buildSettings", {})
        for key in PATH_SETTINGS:
            value = settings.get(key)
            if value and not (APP_DIR / value).exists():
                fail(f"{key} = {value} (config {obj.get('name')}) does not exist on disk")

        base = obj.get("baseConfigurationReference")
        if base:
            ref = objects.get(base, {})
            path = ref.get("path")
            if path and not (APP_DIR / "Supporting" / path).exists():
                fail(f"baseConfigurationReference {path} does not exist on disk")


def check_packages(objects: dict) -> None:
    for obj_id, obj in objects.items():
        if obj.get("isa") != "XCLocalSwiftPackageReference":
            continue
        manifest = APP_DIR / obj["relativePath"] / "Package.swift"
        if not manifest.exists():
            fail(f"local package {obj['relativePath']} has no Package.swift")


def check_scheme(target_ids: dict) -> None:
    if not SCHEME.exists():
        fail("shared scheme is missing — `xcodebuild -scheme CarDash` would fail")
        return
    tree = ET.parse(SCHEME)
    referenced = {
        ref.get("BlueprintIdentifier") for ref in tree.iter("BuildableReference")
    }
    unknown = referenced - set(target_ids)
    if unknown:
        fail(f"scheme references unknown target identifiers: {sorted(unknown)}")

    for ref in tree.iter("BuildableReference"):
        blueprint = ref.get("BlueprintIdentifier")
        target = target_ids.get(blueprint)
        if target and ref.get("BlueprintName") != target.get("name"):
            fail(
                f"scheme BlueprintName {ref.get('BlueprintName')!r} does not match "
                f"target name {target.get('name')!r}"
            )


def check_info_plist() -> None:
    info_path = APP_DIR / "Supporting" / "Info.plist"
    with info_path.open("rb") as handle:
        info = plistlib.load(handle)

    for key in REQUIRED_INFO_KEYS:
        if key not in info:
            fail(f"Info.plist is missing {key}")

    modes = set(info.get("UIBackgroundModes", []))
    if modes != {"audio", "location"}:
        fail(f"UIBackgroundModes should be exactly audio+location, got {sorted(modes)}")

    if "spotify" not in info.get("LSApplicationQueriesSchemes", []):
        fail("LSApplicationQueriesSchemes must contain 'spotify'")

    if "NSContactsUsageDescription" in info:
        fail(
            "NSContactsUsageDescription present — the app uses the no-authorization "
            "contact picker, so this prompt should not be requested"
        )

    orientations = set(info.get("UISupportedInterfaceOrientations", []))
    if orientations != {
        "UIInterfaceOrientationLandscapeLeft",
        "UIInterfaceOrientationLandscapeRight",
    }:
        fail(f"iPhone orientations should be landscape-only, got {sorted(orientations)}")


def main() -> int:
    if not PROJECT.exists():
        print(f"error: {PROJECT} not found", file=sys.stderr)
        return 1

    with PROJECT.open("rb") as handle:
        try:
            project = plistlib.load(handle)
        except Exception as exc:  # noqa: BLE001 - the message is the useful part
            print(f"error: project.pbxproj does not parse as a plist: {exc}", file=sys.stderr)
            return 1

    objects = project.get("objects", {})
    root = project.get("rootObject", "")

    check_object_graph(objects, root)
    targets, names = check_targets(objects)
    check_build_settings(objects)
    check_packages(objects)
    check_scheme(targets)
    check_info_plist()

    if errors:
        print(f"{len(errors)} problem(s) found in the Xcode project:\n", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    print(
        f"project.pbxproj OK — {len(objects)} objects, "
        f"targets: {', '.join(sorted(names))}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
