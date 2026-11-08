#!/usr/bin/env python3
"""Cross-platform build script for the standalone Word engine.

PyInstaller does not cross-compile: run this on each target OS (or in a CI
matrix) to produce that platform's executable.

Examples:
    python build.py
    python build.py --onedir
    python build.py --outdir ../windows-x64
    python build.py --no-install
"""

from __future__ import annotations

import argparse
import os
import platform
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def run(cmd: list[str]) -> None:
    print("+ " + " ".join(cmd), flush=True)
    subprocess.check_call(cmd, cwd=str(ROOT))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Build office_word executable.")
    parser.add_argument(
        "--outdir",
        default="dist",
        help="Output directory (default: dist). Relative paths are relative to this file.",
    )
    parser.add_argument("--name", default="office_word", help="Executable name.")
    parser.add_argument(
        "--onedir",
        action="store_true",
        help="Build a directory instead of a single file (faster startup, fewer AV false positives).",
    )
    parser.add_argument(
        "--no-install",
        action="store_true",
        help="Do not run pip install before building.",
    )
    parser.add_argument(
        "--skip-smoke",
        action="store_true",
        help="Do not run the capabilities smoke test after building.",
    )
    args = parser.parse_args(argv)

    outdir = Path(args.outdir)
    if not outdir.is_absolute():
        outdir = (ROOT / outdir).resolve()
    outdir.mkdir(parents=True, exist_ok=True)

    print(f"Platform: {platform.system()} {platform.machine()}")
    print(f"Python:   {sys.version.split()[0]} ({sys.executable})")
    print(f"Output:   {outdir}")
    print()

    if not args.no_install:
        run([sys.executable, "-m", "pip", "install", "-r", str(ROOT / "requirements.txt")])
        run([sys.executable, "-m", "pip", "install", "pyinstaller"])

    cmd = [
        sys.executable,
        "-m",
        "PyInstaller",
        "--noconfirm",
        "--clean",
        "--name",
        args.name,
        "--collect-data",
        "docx",
        "--distpath",
        str(outdir),
        "--workpath",
        str(ROOT / "build"),
        "--specpath",
        str(ROOT / "build"),
    ]
    cmd.append("--onedir" if args.onedir else "--onefile")
    cmd.append(str(ROOT / "office_word.py"))
    run(cmd)

    suffix = ".exe" if os.name == "nt" else ""
    if args.onedir:
        exe = outdir / args.name / f"{args.name}{suffix}"
    else:
        exe = outdir / f"{args.name}{suffix}"

    if not exe.is_file():
        # PyInstaller onedir layout can vary slightly; report what we have.
        candidates = sorted(outdir.rglob(f"{args.name}*"))
        raise SystemExit(f"Build failed: {exe} not found. Candidates: {candidates}")

    print()
    print(f"Built: {exe}")

    if not args.skip_smoke:
        print("Smoke test: office_word capabilities")
        proc = subprocess.run(
            [str(exe), "capabilities"],
            cwd=str(ROOT),
            encoding="utf-8",
            capture_output=True,
            timeout=60,
        )
        if proc.returncode != 0:
            print(proc.stdout)
            print(proc.stderr, file=sys.stderr)
            raise SystemExit(f"Smoke test failed with exit code {proc.returncode}")
        print(proc.stdout.strip()[:500])

    print()
    print("Note: this binary is for the current OS/architecture only.")
    print("Build separately on Windows, macOS and Linux; PyInstaller cannot cross-compile.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
