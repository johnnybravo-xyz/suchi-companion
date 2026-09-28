#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Build the iOS simulator app without passing the caller's secret environment."""

from __future__ import annotations

import argparse
import gzip
import os
from pathlib import Path
import re
import secrets
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
TOOL_PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
ALLOWED_PARENT_VARIABLES = (
    "HOME",
    "TMPDIR",
    "USER",
    "LOGNAME",
    "LANG",
    "LC_ALL",
    "FLUTTER_ROOT",
    "DEVELOPER_DIR",
)
SENSITIVE_VARIABLE = re.compile(
    r"(?:TOKEN|SECRET|PASSWORD|PASSWD|PRIVATE_KEY|API_KEY|CREDENTIAL|AUTH|SSH_AUTH_SOCK)",
    re.IGNORECASE,
)
CANARY_VARIABLE = "SUCHI_XCODE_SECRET_CANARY"


def isolated_environment(parent: dict[str, str]) -> dict[str, str]:
    environment = {
        name: parent[name]
        for name in ALLOWED_PARENT_VARIABLES
        if parent.get(name)
    }
    tool_path = TOOL_PATH
    if flutter_root := parent.get("FLUTTER_ROOT"):
        flutter_bin = Path(flutter_root).resolve() / "bin"
        if not (flutter_bin / "flutter").is_file():
            raise SystemExit(f"FLUTTER_ROOT does not contain bin/flutter: {flutter_root}")
        tool_path = f"{flutter_bin}:{tool_path}"
    environment.update(
        PATH=tool_path,
        CI="true",
        GIT_TERMINAL_PROMPT="0",
    )
    return environment


def inherited_secret_values(parent: dict[str, str]) -> dict[str, bytes]:
    return {
        name: value.encode()
        for name, value in parent.items()
        if SENSITIVE_VARIABLE.search(name) and len(value.encode()) >= 8
    }


def file_contains_any(path: Path, markers: dict[str, bytes]) -> set[str]:
    if path.suffix == ".xcactivitylog":
        try:
            data = gzip.decompress(path.read_bytes())
        except (OSError, EOFError):
            return set()
        return {name for name, marker in markers.items() if marker in data}

    longest = max((len(marker) for marker in markers.values()), default=1)
    found: set[str] = set()
    overlap = b""
    try:
        with path.open("rb") as handle:
            while chunk := handle.read(1024 * 1024):
                data = overlap + chunk
                found.update(name for name, marker in markers.items() if marker in data)
                if len(found) == len(markers):
                    break
                overlap = data[-(longest - 1) :] if longest > 1 else b""
    except OSError:
        return set()
    return found


def find_secret_leaks(root: Path, markers: dict[str, bytes]) -> dict[str, list[str]]:
    leaks: dict[str, list[str]] = {}
    if not markers:
        return leaks
    for path in root.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        names = file_contains_any(path, markers)
        if names:
            leaks[str(path.relative_to(root))] = sorted(names)
    return leaks


def run(command: list[str], environment: dict[str, str]) -> None:
    subprocess.run(command, cwd=ROOT, env=environment, check=True)


def build(canary: bool) -> None:
    parent = dict(os.environ)
    if canary:
        parent[CANARY_VARIABLE] = "suchi-xcode-canary-" + secrets.token_hex(32)
    markers = inherited_secret_values(parent)
    environment = isolated_environment(parent)
    inherited_names = sorted(set(markers) & set(environment))
    if inherited_names:
        raise SystemExit(
            "isolated Xcode environment contains secret-bearing variables: "
            + ", ".join(inherited_names)
        )

    run(
        ["flutter", "--suppress-analytics", "pub", "get", "--enforce-lockfile"],
        environment,
    )
    run(
        [
            "flutter",
            "--suppress-analytics",
            "build",
            "ios",
            "--simulator",
            "--debug",
            "--config-only",
            "--no-codesign",
            "--no-pub",
        ],
        environment,
    )
    with tempfile.TemporaryDirectory(prefix="suchi-xcode-") as directory:
        derived_data = Path(directory)
        run(
            [
                "xcodebuild",
                "-workspace",
                str(ROOT / "ios/Runner.xcworkspace"),
                "-scheme",
                "Runner",
                "-configuration",
                "Debug",
                "-sdk",
                "iphonesimulator",
                "-destination",
                "generic/platform=iOS Simulator",
                "-derivedDataPath",
                str(derived_data),
                "-hideShellScriptEnvironment",
                "CODE_SIGNING_ALLOWED=NO",
                "FLUTTER_BUILD_MODE=debug",
                "build",
            ],
            environment,
        )
        leaks = find_secret_leaks(derived_data, markers)
        if leaks:
            details = "; ".join(
                f"{path}: {','.join(names)}" for path, names in sorted(leaks.items())
            )
            raise SystemExit("Xcode retained inherited secret values: " + details)

    if canary:
        print("Xcode secret canary passed: inherited secret values were absent from build logs.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--canary",
        action="store_true",
        help="add a synthetic parent secret and prove it is absent from Xcode output",
    )
    arguments = parser.parse_args()
    build(arguments.canary)


if __name__ == "__main__":
    main()
