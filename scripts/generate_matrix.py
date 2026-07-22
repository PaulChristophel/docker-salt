#!/usr/bin/env python3
"""Validate the Salt image configuration and emit the release matrix."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


class ConfigurationError(ValueError):
    """Raised when images.json cannot describe a safe build matrix."""


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", type=Path, help="path to images.json")
    parser.add_argument(
        "--pretty",
        action="store_true",
        help="indent the generated JSON for local inspection",
    )
    return parser.parse_args()


def require_string(mapping: dict[str, Any], key: str, context: str) -> str:
    """Return a required, non-empty string from a configuration object."""
    value = mapping.get(key)
    if not isinstance(value, str) or not value:
        raise ConfigurationError(f"{context}.{key} must be a non-empty string")
    return value


def require_objects(config: dict[str, Any], key: str) -> list[dict[str, Any]]:
    """Return a required list containing only JSON objects."""
    value = config.get(key)
    if not isinstance(value, list) or not value:
        raise ConfigurationError(f"{key} must be a non-empty array")
    if not all(isinstance(item, dict) for item in value):
        raise ConfigurationError(f"every {key} entry must be an object")
    return value


def unique_index(
    entries: list[dict[str, Any]], key: str, context: str
) -> dict[str, dict[str, Any]]:
    """Index configuration objects and reject duplicate identifiers."""
    index: dict[str, dict[str, Any]] = {}
    for position, entry in enumerate(entries):
        name = require_string(entry, key, f"{context}[{position}]")
        if name in index:
            raise ConfigurationError(f"duplicate {context} identifier: {name}")
        index[name] = entry
    return index


def require_string_list(mapping: dict[str, Any], key: str, context: str) -> list[str]:
    """Return a required list of non-empty strings."""
    value = mapping.get(key)
    if (
        not isinstance(value, list)
        or not value
        or not all(isinstance(item, str) and item for item in value)
    ):
        raise ConfigurationError(f"{context}.{key} must be a non-empty string array")
    return value


def validate_stable_pin(root: Path, requirements: str, expected_version: str) -> None:
    """Ensure a stable requirements file installs the version used in its tags."""
    contents = (root / requirements).read_text(encoding="utf-8").splitlines()
    expected = f"salt=={expected_version}"
    if expected not in contents:
        raise ConfigurationError(f"{requirements} does not contain {expected}")


def generate_matrix(config_path: Path) -> list[dict[str, str]]:
    """Load, validate, and expand a Salt image configuration."""
    config = json.loads(config_path.read_text(encoding="utf-8"))
    if not isinstance(config, dict):
        raise ConfigurationError("the configuration root must be an object")

    require_string(config, "image", "configuration")
    require_string(config, "platform", "configuration")
    python_entries = require_objects(config, "python")
    salt_entries = require_objects(config, "salt")
    profile_entries = require_objects(config, "profiles")
    variant_entries = require_objects(config, "variants")

    python_index = unique_index(python_entries, "version", "python")
    salt_index = unique_index(salt_entries, "name", "salt")
    unique_index(profile_entries, "name", "profiles")
    unique_index(variant_entries, "name", "variants")
    root = config_path.resolve().parent
    matrix: list[dict[str, str]] = []

    for variant_position, variant in enumerate(variant_entries):
        variant_context = f"variants[{variant_position}]"
        variant_name = require_string(variant, "name", variant_context)
        variant_tag = variant.get("tag", variant_name)
        if not isinstance(variant_tag, str) or not variant_tag:
            raise ConfigurationError(
                f"{variant_context}.tag must be a non-empty string"
            )
        dockerfile = require_string(variant, "dockerfile", variant_context)
        if not (root / dockerfile).is_file():
            raise ConfigurationError(f"Dockerfile does not exist: {dockerfile}")

        python_versions = require_string_list(variant, "python", variant_context)
        salt_names = require_string_list(variant, "salt", variant_context)
        unknown_python = sorted(set(python_versions) - python_index.keys())
        unknown_salt = sorted(set(salt_names) - salt_index.keys())
        if unknown_python:
            raise ConfigurationError(
                f"{variant_context}.python contains unknown versions: "
                + ", ".join(unknown_python)
            )
        if unknown_salt:
            raise ConfigurationError(
                f"{variant_context}.salt contains unknown channels: "
                + ", ".join(unknown_salt)
            )

        for python_version in python_versions:
            python_entry = python_index[python_version]
            python_release = require_string(
                python_entry, "debian_release", f"python[{python_version}]"
            )
            for salt_name in salt_names:
                salt_entry = salt_index[salt_name]
                salt_requirements = require_string(
                    salt_entry, "requirements", f"salt[{salt_name}]"
                )
                channel = require_string(salt_entry, "channel", f"salt[{salt_name}]")
                if channel not in {"stable", "development"}:
                    raise ConfigurationError(
                        f"salt[{salt_name}].channel must be stable or development"
                    )
                development = channel == "development"
                salt_version = salt_entry.get("version", "")
                if not isinstance(salt_version, str):
                    raise ConfigurationError(
                        f"salt[{salt_name}].version must be a string"
                    )
                if channel == "stable" and (not salt_version):
                    raise ConfigurationError(
                        f"salt[{salt_name}].version is required for a stable channel"
                    )
                if channel == "development" and salt_version:
                    raise ConfigurationError(
                        f"salt[{salt_name}].version is not valid for a development channel"
                    )

                for profile_position, profile in enumerate(profile_entries):
                    profile_context = f"profiles[{profile_position}]"
                    profile_name = require_string(profile, "name", profile_context)
                    requirements_suffix = profile.get("requirements_suffix", "")
                    tag_suffix = profile.get("tag_suffix", "")
                    if not isinstance(requirements_suffix, str) or not isinstance(
                        tag_suffix, str
                    ):
                        raise ConfigurationError(
                            f"{profile_context} suffixes must be strings"
                        )
                    requirements = (
                        f"requirements-{salt_requirements}{requirements_suffix}.txt"
                    )
                    if not (root / requirements).is_file():
                        raise ConfigurationError(
                            f"requirements file does not exist: {requirements}"
                        )
                    if channel == "stable":
                        validate_stable_pin(root, requirements, salt_version)

                    development_suffix = "-dev" if development else ""
                    matrix.append(
                        {
                            "python": python_version,
                            "python_release": python_release,
                            "salt": salt_name,
                            "salt_version": salt_version,
                            "channel": channel,
                            "profile": profile_name,
                            "variant": variant_name,
                            "dockerfile": dockerfile,
                            "requirements": requirements,
                            "tag": (
                                f"{python_version}-{salt_name}{tag_suffix}-"
                                f"{variant_tag}{development_suffix}"
                            ),
                            "version_tag": (
                                f"{python_version}-{salt_version}{tag_suffix}-"
                                f"{variant_tag}"
                                if salt_version
                                else ""
                            ),
                            "sha_prefix": f"{python_version}-{salt_name}-",
                            "sha_suffix": (
                                f"{tag_suffix}-{variant_tag}{development_suffix}"
                            ),
                        }
                    )

    rolling_tags = [entry["tag"] for entry in matrix]
    if len(rolling_tags) != len(set(rolling_tags)):
        raise ConfigurationError("the generated matrix contains duplicate tags")
    return matrix


def main() -> int:
    """Run the command-line matrix generator."""
    args = parse_args()
    try:
        matrix = generate_matrix(args.config)
    except (ConfigurationError, OSError, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    if args.pretty:
        json.dump(matrix, sys.stdout, indent=2)
    else:
        json.dump(matrix, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
