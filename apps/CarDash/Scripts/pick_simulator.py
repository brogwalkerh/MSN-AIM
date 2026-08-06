#!/usr/bin/env python3
"""Print the UDID of a usable iPhone simulator on this machine.

`xcodebuild test -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'` is the
usual incantation and it is brittle: the device names and installed runtimes on
GitHub's macOS images change without notice, and the failure ("Unable to find a
destination matching the provided destination specifier") names the destination string
rather than the reason. Resolving a concrete UDID from whatever is actually installed
sidesteps the whole class of problem.

Prefers the newest iOS runtime available, and the newest-sounding iPhone within it.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys


def runtime_sort_key(identifier: str) -> tuple[int, ...]:
    """Sort runtime identifiers numerically, so iOS-26-10 beats iOS-26-2."""
    return tuple(int(part) for part in re.findall(r"\d+", identifier)) or (0,)


def main() -> int:
    raw = subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "--json"]
    )
    devices = json.loads(raw)["devices"]

    candidates = []
    for runtime in sorted(devices, key=runtime_sort_key):
        if "iOS" not in runtime:
            continue
        for device in devices[runtime]:
            if device.get("isAvailable", True) and device["name"].startswith("iPhone"):
                candidates.append((runtime, device))

    if not candidates:
        print("no available iPhone simulator on this machine", file=sys.stderr)
        print("installed runtimes: " + ", ".join(sorted(devices)), file=sys.stderr)
        return 1

    runtime, device = candidates[-1]
    print(device["udid"])
    print(f"selected {device['name']} on {runtime}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
