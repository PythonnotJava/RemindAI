#!/usr/bin/env python3
"""Standalone Excel (.xlsx/.xls) read engine.

This file is independent from RemindAI/Flutter.  Run it directly:

    python office_excel.py read --input request.json
    python office_excel.py file --input request.json
    python office_excel.py capabilities
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from excel_engine.cli import main  # noqa: E402

if __name__ == "__main__":
    raise SystemExit(main())
