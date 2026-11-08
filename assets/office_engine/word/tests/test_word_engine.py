from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from docx import Document
from docx.enum.table import WD_ALIGN_VERTICAL, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from PIL import Image

WORD_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(WORD_DIR))

from word_engine.protocol import EngineError  # noqa: E402
from word_engine.reader import read_word  # noqa: E402
from word_engine.writer import create_word, edit_word, file_operation  # noqa: E402


def make_image(path: Path) -> None:
    Image.new("RGB", (240, 120), (220, 60, 60)).save(path)


def make_docx(path: Path, image: Path) -> None:
    doc = Document()
    doc.add_heading("测试文档", level=1)
    doc.add_paragraph("这是第一段，包含旧内容，需要替换。")
    table = doc.add_table(rows=2, cols=2)
    table.style = "Table Grid"
    table.cell(0, 0).text = "名称"
    table.cell(0, 1).text = "数值"
    table.cell(1, 0).text = "A"
    table.cell(1, 1).text = "1"
    doc.add_picture(str(image))
    caption = doc.add_paragraph("图1 测试图片")
    caption.style = "Caption"
    doc.add_paragraph("结尾段落")
    doc.save(str(path))


class WordEngineTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="office_word_test_")
        self.root = Path(self.tmp.name)
        self.image = self.root / "source.png"
        make_image(self.image)
        self.source = self.root / "source.docx"
        make_docx(self.source, self.image)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_read_docx_blocks_images_captions(self) -> None:
        output = self.root / "read_out"
        result = read_word(
            {
                "path": str(self.source),
                "output_dir": str(output),
                "options": {"max_chars": 100000},
            }
        )
        self.assertEqual(result["status"], "ok")
        self.assertTrue((output / "document.md").is_file())
        self.assertTrue((output / "document.text.md").is_file())
        self.assertTrue((output / "document.json").is_file())
        self.assertTrue((output / "meta.json").is_file())
        self.assertEqual(len(result["images"]), 1)
        image = result["images"][0]
        self.assertEqual(image["label"], "图1")
        self.assertIn("图1", image["caption"])
        self.assertTrue((output / image["path"]).is_file())

        blocks = result["blocks"]
        self.assertTrue(any(b["type"] == "heading" for b in blocks))
        self.assertTrue(any(b["type"] == "table" for b in blocks))
        self.assertTrue(any(b["type"] == "image" for b in blocks))
        self.assertTrue(all("id" in b for b in blocks))

        full_md = (output / "document.md").read_text(encoding="utf-8")
        text_md = (output / "document.text.md").read_text(encoding="utf-8")
        self.assertIn("![图1 测试图片](images/图1.png)", full_md)
        self.assertIn("[图1 测试图片]", text_md)
        self.assertEqual(len(result["document_hash"]), 64)

    def test_edit_replace_insert_delete_and_table(self) -> None:
        read_result = read_word(
            {"path": str(self.source), "output_dir": str(self.root / "read_out")}
        )
        blocks = read_result["blocks"]
        target = next(b for b in blocks if b.get("text") and "旧内容" in b["text"])
        ending = next(b for b in blocks if b.get("text") == "结尾段落")

        output = self.root / "edited.docx"
        result = edit_word(
            {
                "source": str(self.source),
                "output": str(output),
                "document_hash": read_result["document_hash"],
                "options": {"highlight": "visual", "keep_deleted": False},
                "operations": [
                    {
                        "op": "replace_text",
                        "block_id": target["id"],
                        "find": "旧内容",
                        "replace": "新内容",
                    },
                    {
                        "op": "insert_paragraph_after",
                        "block_id": target["id"],
                        "text": "插入段落",
                    },
                    {
                        "op": "set_table_cell",
                        "table_id": "t0",
                        "row": 1,
                        "col": 1,
                        "value": "42",
                    },
                    {"op": "center_tables"},
                    {"op": "delete_block", "block_id": ending["id"]},
                ],
            }
        )
        self.assertEqual(result["status"], "ok")
        self.assertTrue(output.is_file())
        self.assertEqual(len(result["changes"]), 5)
        self.assertTrue(Path(result["changes_json"]).is_file())
        self.assertTrue(Path(result["changes_md"]).is_file())

        doc = Document(str(output))
        texts = [p.text for p in doc.paragraphs]
        self.assertTrue(any("新内容" in t for t in texts))
        self.assertTrue(any(t == "插入段落" for t in texts))
        self.assertFalse(any(t == "结尾段落" for t in texts))
        self.assertEqual(doc.tables[0].cell(1, 1).text, "42")
        self.assertEqual(doc.tables[0].alignment, WD_TABLE_ALIGNMENT.CENTER)
        self.assertEqual(
            doc.tables[0].cell(1, 1).vertical_alignment,
            WD_ALIGN_VERTICAL.CENTER,
        )
        self.assertEqual(
            doc.tables[0].cell(1, 1).paragraphs[0].alignment,
            WD_ALIGN_PARAGRAPH.CENTER,
        )
        # Source must remain untouched.
        source_doc = Document(str(self.source))
        self.assertTrue(any("旧内容" in p.text for p in source_doc.paragraphs))

    def test_delete_numbered_item_renumbers_following(self) -> None:
        path = self.root / "numbered.docx"
        doc = Document()
        doc.add_paragraph("（1）第一项")
        doc.add_paragraph("（2）第二项")
        doc.add_paragraph("（3）第三项")
        doc.add_paragraph("1.4组织")
        doc.save(str(path))

        read_result = read_word(
            {"path": str(path), "output_dir": str(self.root / "numbered_read")}
        )
        target = next(
            b for b in read_result["blocks"] if "（2）第二项" in b.get("text", "")
        )
        output = self.root / "numbered_edited.docx"
        result = edit_word(
            {
                "source": str(path),
                "output": str(output),
                "operations": [{"op": "delete_block", "block_id": target["id"]}],
            }
        )
        self.assertEqual(result["status"], "ok")
        self.assertTrue(result["changes"][0]["renumbered"])
        texts = [p.text for p in Document(str(output)).paragraphs]
        self.assertIn("（1）第一项", texts)
        self.assertNotIn("（2）第二项", texts)
        self.assertIn("（2）第三项", texts)
        self.assertNotIn("（3）第三项", texts)

    def test_stale_hash_is_rejected(self) -> None:
        with self.assertRaises(EngineError) as ctx:
            edit_word(
                {
                    "source": str(self.source),
                    "output": str(self.root / "bad.docx"),
                    "document_hash": "deadbeef",
                    "operations": [
                        {
                            "op": "replace_text",
                            "block_id": "p1",
                            "find": "旧内容",
                            "replace": "x",
                        }
                    ],
                }
            )
        self.assertEqual(ctx.exception.code, "STALE_DOCUMENT")

    def test_create_from_markdown(self) -> None:
        output = self.root / "created.docx"
        markdown = (
            "# 新文档\n\n"
            "这是正文。\n\n"
            "| A | B |\n|---|---|\n| 1 | 2 |\n\n"
            f"![图1 测试图片]({self.image})\n"
        )
        result = create_word({"output": str(output), "markdown": markdown})
        self.assertEqual(result["status"], "ok")
        self.assertTrue(output.is_file())

        read_result = read_word(
            {"path": str(output), "output_dir": str(self.root / "created_out")}
        )
        self.assertTrue(any(b["type"] == "heading" for b in read_result["blocks"]))
        self.assertTrue(any(b["type"] == "table" for b in read_result["blocks"]))
        self.assertEqual(len(read_result["images"]), 1)

    def test_file_info_and_trash_delete(self) -> None:
        info = file_operation({"operation": "info", "path": str(self.source)})
        self.assertEqual(info["status"], "ok")
        self.assertTrue(info["docx_zip_ok"])

        deleted = file_operation(
            {"operation": "delete", "path": str(self.source), "mode": "trash"}
        )
        self.assertEqual(deleted["status"], "ok")
        self.assertFalse(self.source.exists())
        self.assertTrue(Path(deleted["trashed_to"]).is_file())

    def test_cli_read_json_stdout(self) -> None:
        request = {
            "action": "read",
            "path": str(self.source),
            "output_dir": str(self.root / "cli_out"),
        }
        proc = subprocess.run(
            [sys.executable, str(WORD_DIR / "office_word.py"), "read"],
            input=json.dumps(request, ensure_ascii=False),
            encoding="utf-8",
            capture_output=True,
            cwd=str(WORD_DIR),
            timeout=60,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        payload = json.loads(proc.stdout)
        self.assertEqual(payload["status"], "ok")
        self.assertTrue(payload["blocks"])

    def test_capabilities(self) -> None:
        proc = subprocess.run(
            [sys.executable, str(WORD_DIR / "office_word.py"), "capabilities"],
            encoding="utf-8",
            capture_output=True,
            cwd=str(WORD_DIR),
            timeout=60,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        payload = json.loads(proc.stdout)
        self.assertEqual(payload["status"], "ok")
        self.assertIn("docx", payload["formats"]["input"])


if __name__ == "__main__":
    unittest.main()
