from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path

from openpyxl import Workbook
from openpyxl.drawing.image import Image as XLImage
from PIL import Image

EXCEL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EXCEL_DIR))

from excel_engine.reader import file_operation, read_excel  # noqa: E402


def make_image(path: Path) -> None:
    Image.new("RGB", (40, 20), (20, 120, 220)).save(path)


def make_xlsx(path: Path, image: Path) -> None:
    wb = Workbook()
    ws = wb.active
    ws.title = "Data"
    ws.append(["Name", "Qty", "Total"])
    ws.append(["A", 10, "=B2*2"])
    ws.append(["B", 20, "=B3*2"])
    ws.append(["C", 30, "=B4*2"])
    ws["A6"] = "Merged"
    ws.merge_cells("A6:B6")
    ws.row_dimensions[5].hidden = True
    ws.column_dimensions["D"].hidden = True
    ws.add_image(XLImage(str(image)), "E2")

    wide = wb.create_sheet("Wide")
    for c in range(1, 101):
        wide.cell(1, c, f"H{c}")
    for r in range(2, 5):
        for c in range(1, 101):
            wide.cell(r, c, r * c)
    wb.save(str(path))


class ExcelEngineTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="office_excel_test_")
        self.root = Path(self.tmp.name)
        self.image = self.root / "img.png"
        make_image(self.image)
        self.source = self.root / "source.xlsx"
        make_xlsx(self.source, self.image)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_read_xlsx_workbook_sheets_formulas_merges_images(self) -> None:
        out = self.root / "out"
        result = read_excel(
            {
                "path": str(self.source),
                "output_dir": str(out),
                "options": {
                    "max_rows": 10,
                    "max_cols": 10,
                    "include_images": True,
                },
            }
        )
        self.assertEqual(result["status"], "ok")
        self.assertEqual(len(result["sheets"]), 2)
        data = result["sheets"][0]
        self.assertEqual(data["name"], "Data")
        self.assertEqual(data["rows"], 6)
        self.assertGreaterEqual(data["formula_count"], 3)
        self.assertIn("A6:B6", data["merged"])
        self.assertIn(5, data["hidden_rows"])
        self.assertIn("D", data["hidden_cols"])
        self.assertEqual(len(data["images"]), 1)
        self.assertTrue((out / data["csv"]).is_file())
        self.assertTrue((out / "document.md").is_file())
        self.assertTrue((out / "document.json").is_file())
        self.assertTrue((out / "meta.json").is_file())

        md = (out / "document.md").read_text(encoding="utf-8")
        self.assertIn("Sheet: Data", md)
        self.assertIn("公式", md)
        self.assertIn("完整数据", md)

        wide = result["sheets"][1]
        self.assertEqual(wide["name"], "Wide")
        self.assertEqual(wide["columns"], 100)
        self.assertLessEqual(len(wide["columns_meta"]), 10)
        self.assertTrue(wide["truncated"])

    def test_sheet_and_range_filter(self) -> None:
        result = read_excel(
            {
                "path": str(self.source),
                "output_dir": str(self.root / "filtered"),
                "options": {
                    "sheet": "Data",
                    "range": "A1:C4",
                    "max_rows": 10,
                    "max_cols": 10,
                },
            }
        )
        self.assertEqual(result["status"], "ok")
        self.assertEqual(len(result["sheets"]), 1)
        self.assertEqual(result["sheets"][0]["columns"], 3)
        self.assertEqual(result["sheets"][0]["rows"], 4)

    def test_file_info(self) -> None:
        info = file_operation({"operation": "info", "path": str(self.source)})
        self.assertEqual(info["status"], "ok")
        self.assertEqual(info["format"], "xlsx")
        self.assertEqual(len(info["sha256"]), 64)

    @unittest.skipUnless(importlib.util.find_spec("xlwt"), "xlwt not installed")
    def test_read_xls(self) -> None:
        import xlwt

        xls = self.root / "legacy.xls"
        wb = xlwt.Workbook()
        ws = wb.add_sheet("Data")
        ws.write(0, 0, "Name")
        ws.write(0, 1, "Qty")
        ws.write(0, 2, "Date")
        ws.write(1, 0, "A")
        ws.write(1, 1, 10)
        date_style = xlwt.easyxf(num_format_str="YYYY-MM-DD")
        ws.write(1, 2, datetime(2026, 1, 2), date_style)
        ws.write_merge(3, 3, 0, 1, "Merged")
        wb.save(str(xls))

        result = read_excel(
            {
                "path": str(xls),
                "output_dir": str(self.root / "xls_out"),
                "options": {"max_rows": 10, "max_cols": 10},
            }
        )
        self.assertEqual(result["status"], "ok")
        sheet = result["sheets"][0]
        self.assertEqual(sheet["name"], "Data")
        self.assertIn("A4:B4", sheet["merged"])
        self.assertTrue(any("公式文本不可用" in w for w in result["warnings"]))

    def test_cli_read(self) -> None:
        request = {
            "action": "read",
            "path": str(self.source),
            "output_dir": str(self.root / "cli_out"),
            "options": {"max_rows": 5, "max_cols": 5},
        }
        proc = subprocess.run(
            [sys.executable, str(EXCEL_DIR / "office_excel.py"), "read"],
            input=json.dumps(request, ensure_ascii=False),
            encoding="utf-8",
            capture_output=True,
            cwd=str(EXCEL_DIR),
            timeout=60,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        payload = json.loads(proc.stdout)
        self.assertEqual(payload["status"], "ok")
        self.assertEqual(len(payload["sheets"]), 2)

    def test_capabilities(self) -> None:
        proc = subprocess.run(
            [sys.executable, str(EXCEL_DIR / "office_excel.py"), "capabilities"],
            encoding="utf-8",
            capture_output=True,
            cwd=str(EXCEL_DIR),
            timeout=60,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        payload = json.loads(proc.stdout)
        self.assertEqual(payload["status"], "ok")
        self.assertIn("xlsx", payload["formats"]["input"])


if __name__ == "__main__":
    unittest.main()
