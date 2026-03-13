#!/usr/bin/env python3
"""Build a Linux release zip for comfy-sage."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
from datetime import datetime, timezone
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT_DIR = ROOT / "dist"
PAYLOAD_FILES = [
    "launch-comfy.sh",
    "README.md",
    "LICENSE",
    "THIRD_PARTY_NOTICES.md",
    "VERSION",
]


def read_version() -> str:
    return (ROOT / "VERSION").read_text(encoding="utf-8").strip()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_zip_entry(zip_file: ZipFile, source: Path, arcname: str) -> None:
    stat_result = source.stat()
    info = ZipInfo.from_file(source, arcname)
    info.compress_type = ZIP_DEFLATED
    info.external_attr = (stat_result.st_mode & 0xFFFF) << 16
    with source.open("rb") as handle:
        zip_file.writestr(info, handle.read())


def build_release(version: str, output_dir: Path) -> tuple[Path, Path]:
    archive_name = f"comfy-sage-linux-x86_64-v{version}.zip"
    checksum_name = f"{archive_name}.sha256"
    bundle_root = output_dir / f"comfy-sage-linux-x86_64-v{version}"
    archive_path = output_dir / archive_name
    checksum_path = output_dir / checksum_name

    if bundle_root.exists():
        shutil.rmtree(bundle_root)
    output_dir.mkdir(parents=True, exist_ok=True)
    bundle_root.mkdir(parents=True, exist_ok=True)

    for relative_path in PAYLOAD_FILES:
        source = ROOT / relative_path
        destination = bundle_root / relative_path
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)

    build_info = {
        "project": "comfy-sage",
        "version": version,
        "platform": "linux-x86_64",
        "generated_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "payload_files": PAYLOAD_FILES,
    }
    (bundle_root / "BUILD-INFO.json").write_text(
        json.dumps(build_info, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    if archive_path.exists():
        archive_path.unlink()

    with ZipFile(archive_path, "w") as zip_file:
        for source in sorted(bundle_root.rglob("*")):
            if source.is_dir():
                continue
            arcname = source.relative_to(output_dir).as_posix()
            write_zip_entry(zip_file, source, arcname)

    checksum_path.write_text(
        f"{sha256(archive_path)}  {archive_path.name}\n",
        encoding="utf-8",
    )
    return archive_path, checksum_path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--version",
        default=read_version(),
        help="version string to embed in the release archive name",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help="directory where release files should be written",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    archive_path, checksum_path = build_release(args.version, args.output_dir.resolve())
    print(archive_path)
    print(checksum_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
