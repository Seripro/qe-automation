#!/usr/bin/env python3
"""Validate a PWscf.zip archive before extracting it into a work directory."""

from __future__ import annotations

import argparse
import stat
import sys
import zipfile
from pathlib import Path, PurePosixPath


def validate_member(info: zipfile.ZipInfo) -> None:
    name = info.filename
    path = PurePosixPath(name)

    if not name or path.is_absolute() or ".." in path.parts:
        raise ValueError(f"unsafe archive path: {name!r}")
    if not path.parts or path.parts[0] != "PWscf":
        raise ValueError(f"archive entry must be inside PWscf/: {name!r}")

    mode = info.external_attr >> 16
    if stat.S_ISLNK(mode):
        raise ValueError(f"symbolic links are not allowed: {name!r}")
    if info.flag_bits & 0x1:
        raise ValueError(f"encrypted entries are not allowed: {name!r}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Validate a PWscf.zip archive before extraction."
    )
    parser.add_argument("archive", type=Path)
    parser.add_argument("--max-files", type=int, default=1_000)
    parser.add_argument("--max-uncompressed-bytes", type=int, default=2 * 1024**3)
    args = parser.parse_args()

    if args.max_files < 1 or args.max_uncompressed_bytes < 1:
        parser.error("archive limits must be positive")

    try:
        with zipfile.ZipFile(args.archive) as archive:
            members = archive.infolist()
            if len(members) > args.max_files:
                raise ValueError(f"archive has too many entries: {len(members)}")

            names: set[str] = set()
            total_uncompressed_bytes = 0
            has_input = False
            for member in members:
                validate_member(member)
                if member.filename in names:
                    raise ValueError(f"duplicate archive entry: {member.filename!r}")
                names.add(member.filename)
                total_uncompressed_bytes += member.file_size
                if total_uncompressed_bytes > args.max_uncompressed_bytes:
                    raise ValueError(
                        "archive exceeds the uncompressed-size limit: "
                        f"{total_uncompressed_bytes} bytes"
                    )
                if member.filename == "PWscf/pwscf.in":
                    has_input = True

            if not has_input:
                raise ValueError("PWscf/pwscf.in was not found in the archive")
    except (OSError, zipfile.BadZipFile, ValueError) as error:
        print(f"Error: unsafe or invalid PWscf.zip: {error}", file=sys.stderr)
        raise SystemExit(2) from error

    print(
        "ZIP validation passed: "
        f"{len(members)} entries, {total_uncompressed_bytes} uncompressed bytes."
    )


if __name__ == "__main__":
    main()
