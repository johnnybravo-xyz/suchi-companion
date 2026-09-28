#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Synchronize mobile API fixtures from the pinned Suchi server checkout."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
METADATA = ROOT / "tool/toolchain.json"
DESTINATION = ROOT / "test/fixtures/api"


def fail(message: str, code: int = 1) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(code)


def metadata() -> tuple[str, str, int, str]:
    try:
        data = json.loads(METADATA.read_text(encoding="utf-8"))
        server = data["server"]
        revision = server["compatible_ref"]
        tag = server["compatible_tag"]
        api_version = server["api_version"]
        contract = server["mobile_contract"]
    except (OSError, KeyError, TypeError, json.JSONDecodeError) as error:
        fail(f"Invalid server metadata in {METADATA.relative_to(ROOT)}: {error}", 2)
    if not isinstance(revision, str) or re.fullmatch(r"[0-9a-f]{40}", revision) is None:
        fail("compatible_ref must be a full lowercase Git commit", 2)
    if not isinstance(tag, str) or re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag) is None:
        fail("compatible_tag must be a stable semantic-version tag", 2)
    if not isinstance(api_version, int) or api_version < 1:
        fail("api_version must be a positive integer", 2)
    if not isinstance(contract, str) or not contract:
        fail("mobile_contract must be a non-empty string", 2)
    return revision, tag, api_version, contract


def checkout_revision(server_root: Path) -> str:
    try:
        result = subprocess.run(
            ["git", "-C", str(server_root), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        fail(f"Cannot read the server checkout revision: {error}", 2)
    return result.stdout.strip()


def fixture_bytes(server_root: Path, api_version: int, contract: str) -> dict[str, bytes]:
    source = server_root / "core/api/testdata/mobile" / f"v{api_version}"
    if not source.is_dir():
        fail(f"Server fixture directory does not exist: {source}", 2)
    fixtures = {path.name: path.read_bytes() for path in sorted(source.glob("*.json"))}
    if not fixtures:
        fail("Server fixture directory contains no JSON fixtures.", 2)
    try:
        handshake = json.loads(fixtures["handshake.json"])
    except (KeyError, json.JSONDecodeError) as error:
        fail(f"Server handshake fixture is invalid: {error}", 2)
    if (
        handshake.get("product") != "suchi"
        or handshake.get("api_version") != api_version
        or contract not in handshake.get("mobile_contracts", [])
    ):
        fail("Server handshake fixture differs from toolchain metadata.", 2)
    return fixtures


def manifest(fixtures: dict[str, bytes]) -> bytes:
    lines = [f"{hashlib.sha256(content).hexdigest()}  {name}\n" for name, content in fixtures.items()]
    return "".join(lines).encode()


def check(destination: Path, expected: dict[str, bytes]) -> None:
    if not destination.is_dir():
        fail("Mobile fixture directory does not exist.")
    actual_names = {path.name for path in destination.iterdir() if path.is_file()}
    if actual_names != set(expected):
        fail("Mobile fixture file set is out of date.")
    for name, content in expected.items():
        if (destination / name).read_bytes() != content:
            fail(f"{name} is out of date.")
    print("Mobile API fixtures match the pinned server contract.")


def synchronize(destination: Path, expected: dict[str, bytes]) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    for path in destination.iterdir():
        if path.is_file():
            path.unlink()
        elif path.is_dir():
            shutil.rmtree(path)
    for name, content in expected.items():
        (destination / name).write_bytes(content)
    print(f"Synchronized {len(expected) - 1} mobile API fixtures.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--server-root", required=True, type=Path)
    arguments = parser.parse_args()

    revision, tag, api_version, contract = metadata()
    server_root = arguments.server_root.resolve()
    actual_revision = checkout_revision(server_root)
    if actual_revision != revision:
        fail(
            f"Server checkout is {actual_revision}; tool/toolchain.json pins {tag} at {revision}.",
            2,
        )

    fixtures = fixture_bytes(server_root, api_version, contract)
    fixtures["manifest.sha256"] = manifest(fixtures)
    destination = DESTINATION / f"v{api_version}"
    if arguments.check:
        check(destination, fixtures)
    else:
        synchronize(destination, fixtures)


if __name__ == "__main__":
    main()
