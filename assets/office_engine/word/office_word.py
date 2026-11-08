#!/usr/bin/env python3
"""Standalone Office Word engine.

This file is intentionally independent from RemindAI/Flutter.  It can be run
directly during development:

    python office_word.py read --input request.json
    python office_word.py create --input request.json
    python office_word.py edit --input request.json
    python office_word.py file --input request.json

For release, build a single executable with build.ps1 / PyInstaller.
"""

from __future__ import annotations

import os
import sys

# Allow running this file directly from the repository.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from word_engine.cli import main  # noqa: E402

if __name__ == "__main__":
    raise SystemExit(main())
