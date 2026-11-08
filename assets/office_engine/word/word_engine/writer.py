"""DOCX creation and editing."""

from __future__ import annotations

import os
import re
import shutil
import tempfile
import uuid
from pathlib import Path
from typing import Any

from docx import Document
from docx.enum.table import WD_ALIGN_VERTICAL, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_COLOR_INDEX
from docx.oxml.ns import qn
from docx.shared import Cm, RGBColor
from docx.text.paragraph import Paragraph

from .legacy import convert_doc_to_docx
from .protocol import EngineError, ok
from .utils import (
    atomic_write_file,
    cleanup_old_backups,
    ensure_dir,
    now_iso,
    resolve_path,
    sanitize_filename,
    sha256_file,
    timestamp_slug,
    unique_path,
    write_json,
)

_HEADING_RE = re.compile(r"^(#{1,6})\s+(.*)$")
_IMAGE_RE = re.compile(r"^!\[([^\]]*)\]\(([^)]+)\)\s*$")
_BULLET_RE = re.compile(r"^\s*[-*+]\s+(.*)$")
_NUMBER_RE = re.compile(r"^\s*\d+[.)]\s+(.*)$")
_TABLE_SEP_RE = re.compile(
    r"^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$"
)
_NUMBERED_RE = re.compile(r"^(\s*[（(]\s*)(\d+)(\s*[）)]\s*)(.*)$")


def _highlight_paragraph(paragraph) -> None:
    for run in paragraph.runs:
        run.font.highlight_color = WD_COLOR_INDEX.YELLOW
    if not paragraph.runs and paragraph.text:
        run = paragraph.add_run(paragraph.text)
        run.font.highlight_color = WD_COLOR_INDEX.YELLOW


def _mark_deleted(paragraph) -> None:
    for run in paragraph.runs:
        run.font.strike = True
        run.font.color.rgb = RGBColor(0xC0, 0x00, 0x00)
    if not paragraph.runs and paragraph.text:
        run = paragraph.add_run(paragraph.text)
        run.font.strike = True
        run.font.color.rgb = RGBColor(0xC0, 0x00, 0x00)


def _set_style(paragraph, style: str | None) -> None:
    if not style:
        return
    try:
        paragraph.style = style
    except Exception:
        pass


def _add_table(doc, rows: list[list[str]]) -> None:
    if not rows:
        return
    cols = max(len(r) for r in rows)
    table = doc.add_table(rows=len(rows), cols=cols)
    try:
        table.style = "Table Grid"
    except Exception:
        pass
    for r, row in enumerate(rows):
        for c in range(cols):
            table.cell(r, c).text = row[c] if c < len(row) else ""


def _split_table_row(line: str) -> list[str]:
    value = line.strip()
    if value.startswith("|"):
        value = value[1:]
    if value.endswith("|"):
        value = value[:-1]
    return [part.strip() for part in value.split("|")]


def _add_markdown(doc, markdown: str, base_dir: Path, highlight: bool) -> None:
    lines = markdown.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        if not stripped:
            i += 1
            continue

        if stripped.startswith("```"):
            i += 1
            code: list[str] = []
            while i < len(lines) and not lines[i].strip().startswith("```"):
                code.append(lines[i])
                i += 1
            i += 1
            paragraph = doc.add_paragraph("\n".join(code))
            for run in paragraph.runs:
                run.font.name = "Consolas"
            continue

        m = _HEADING_RE.match(stripped)
        if m:
            level = len(m.group(1))
            paragraph = doc.add_heading(m.group(2).strip(), level=level)
            if highlight:
                _highlight_paragraph(paragraph)
            i += 1
            continue

        m = _IMAGE_RE.match(stripped)
        if m:
            alt, src = m.group(1).strip(), m.group(2).strip()
            image_path = resolve_path(src, base_dir)
            if image_path.is_file():
                doc.add_picture(str(image_path))
                if alt:
                    caption = doc.add_paragraph(alt)
                    _set_style(caption, "Caption")
                    if highlight:
                        _highlight_paragraph(caption)
            i += 1
            continue

        # Pipe table: header row followed by a separator row.
        if "|" in stripped and i + 1 < len(lines) and _TABLE_SEP_RE.match(lines[i + 1]):
            rows: list[list[str]] = [_split_table_row(stripped)]
            i += 2
            while i < len(lines) and "|" in lines[i] and lines[i].strip():
                rows.append(_split_table_row(lines[i]))
                i += 1
            _add_table(doc, rows)
            continue

        m = _BULLET_RE.match(line)
        if m:
            paragraph = doc.add_paragraph(m.group(1).strip(), style="List Bullet")
            if highlight:
                _highlight_paragraph(paragraph)
            i += 1
            continue

        m = _NUMBER_RE.match(line)
        if m:
            paragraph = doc.add_paragraph(m.group(1).strip(), style="List Number")
            if highlight:
                _highlight_paragraph(paragraph)
            i += 1
            continue

        # Paragraph: collect consecutive plain lines.
        buffer = [stripped]
        i += 1
        while i < len(lines):
            nxt = lines[i].strip()
            if (
                not nxt
                or _HEADING_RE.match(nxt)
                or _IMAGE_RE.match(nxt)
                or _BULLET_RE.match(nxt)
                or _NUMBER_RE.match(nxt)
                or nxt.startswith("```")
                or (
                    "|" in nxt
                    and i + 1 < len(lines)
                    and _TABLE_SEP_RE.match(lines[i + 1])
                )
            ):
                break
            buffer.append(nxt)
            i += 1
        paragraph = doc.add_paragraph(" ".join(buffer))
        if highlight:
            _highlight_paragraph(paragraph)


def _add_blocks(doc, blocks: list[dict[str, Any]], base_dir: Path, highlight: bool) -> None:
    for block in blocks:
        kind = block.get("type")
        if kind == "heading":
            paragraph = doc.add_heading(
                str(block.get("text") or ""), level=int(block.get("level") or 1)
            )
            if highlight:
                _highlight_paragraph(paragraph)
        elif kind in ("paragraph", "textbox"):
            paragraph = doc.add_paragraph(str(block.get("text") or ""))
            _set_style(paragraph, block.get("style"))
            if highlight:
                _highlight_paragraph(paragraph)
        elif kind == "list_item":
            style = "List Number" if block.get("list") == "number" else "List Bullet"
            paragraph = doc.add_paragraph(str(block.get("text") or ""), style=style)
            if highlight:
                _highlight_paragraph(paragraph)
        elif kind == "table":
            rows = block.get("rows") or []
            if isinstance(rows, list):
                _add_table(doc, [[str(v) for v in row] for row in rows if isinstance(row, list)])
        elif kind == "image":
            path_value = block.get("path")
            if not path_value:
                continue
            image_path = resolve_path(str(path_value), base_dir)
            if image_path.is_file():
                doc.add_picture(str(image_path))
                caption = block.get("caption") or block.get("alt") or ""
                if caption:
                    p = doc.add_paragraph(str(caption))
                    _set_style(p, "Caption")


def create_word(request: dict[str, Any]) -> dict[str, Any]:
    output_value = request.get("output") or request.get("path")
    if not isinstance(output_value, str) or not output_value.strip():
        raise EngineError("INVALID_REQUEST", "create 缺少 output 参数。")
    base_dir = resolve_path(request.get("base_dir") or ".")
    output = resolve_path(output_value, base_dir)
    if output.suffix.lower() != ".docx":
        raise EngineError(
            "UNSUPPORTED_OUTPUT_FORMAT",
            "当前引擎只输出 .docx。",
            hint="请把 output 改成 .docx。",
        )
    overwrite = request.get("overwrite") is True
    if output.exists() and not overwrite:
        output = unique_path(output)
    ensure_dir(output.parent)

    options = request.get("options") or {}
    if not isinstance(options, dict):
        options = {}
    highlight = str(options.get("highlight") or "none").lower() == "visual"
    if str(options.get("highlight") or "").lower() == "track_changes":
        raise EngineError(
            "UNSUPPORTED_OPTION",
            "MVP 不支持真正的 Word 修订（track changes）。",
            hint="请使用 highlight=visual，或后续版本。",
        )

    doc = Document()
    title = request.get("title")
    if isinstance(title, str) and title.strip():
        doc.core_properties.title = title.strip()

    blocks = request.get("blocks")
    markdown = request.get("markdown")
    if isinstance(blocks, list) and blocks:
        _add_blocks(doc, [b for b in blocks if isinstance(b, dict)], base_dir, highlight)
    elif isinstance(markdown, str) and markdown.strip():
        _add_markdown(doc, markdown, base_dir, highlight)
    else:
        raise EngineError(
            "INVALID_REQUEST",
            "create 需要 markdown 或非空 blocks。",
        )

    # Extra images appended after the content (useful for programmatic callers).
    images = request.get("images")
    if isinstance(images, list):
        for image in images:
            if not isinstance(image, dict):
                continue
            path_value = image.get("path")
            if not isinstance(path_value, str):
                continue
            image_path = resolve_path(path_value, base_dir)
            if not image_path.is_file():
                continue
            doc.add_picture(str(image_path))
            caption = image.get("caption") or image.get("alt") or image.get("label") or ""
            if caption:
                p = doc.add_paragraph(str(caption))
                _set_style(p, "Caption")

    tmp = output.parent / f".{output.stem}.tmp-{uuid.uuid4().hex[:8]}.docx"
    try:
        doc.save(str(tmp))
        # Validate before publishing.
        Document(str(tmp))
        atomic_write_file(tmp, output)
        cleanup_old_backups(output.parent)
    finally:
        tmp.unlink(missing_ok=True)

    return ok(
        action="create",
        output=str(output),
        output_format="docx",
        document_hash=sha256_file(output),
        changes=[],
        warnings=[],
        engine_created_at=now_iso(),
    )


def _get_paragraph(doc, block_id: str, mapping: dict[str, Any] | None = None):
    key = str(block_id or "")
    if mapping is not None and key in mapping:
        return mapping[key]
    m = re.fullmatch(r"p(\d+)", key)
    if not m:
        return None
    idx = int(m.group(1))
    if idx < 0 or idx >= len(doc.paragraphs):
        return None
    return doc.paragraphs[idx]


def _get_table(doc, table_id: str, mapping: dict[str, Any] | None = None):
    key = str(table_id or "")
    if mapping is not None and key in mapping:
        return mapping[key]
    m = re.fullmatch(r"t(\d+)", key)
    if not m:
        return None
    idx = int(m.group(1))
    if idx < 0 or idx >= len(doc.tables):
        return None
    return doc.tables[idx]


def _replace_once(
    paragraph,
    find: str,
    replace: str,
    highlight: bool,
    keep_deleted: bool,
    warnings: list[str],
) -> bool:
    runs = list(paragraph.runs)
    if not runs:
        text = paragraph.text
        idx = text.find(find)
        if idx < 0:
            return False
        if keep_deleted and replace == "":
            paragraph.text = text
            _mark_deleted(paragraph)
            return True
        paragraph.text = text[:idx] + replace + text[idx + len(find) :]
        if highlight:
            _highlight_paragraph(paragraph)
        return True

    full = "".join(r.text for r in runs)
    idx = full.find(find)
    if idx < 0:
        return False

    ranges: list[tuple[int, int, Any]] = []
    pos = 0
    for run in runs:
        start = pos
        end = pos + len(run.text)
        ranges.append((start, end, run))
        pos = end

    start_run = None
    end_run = None
    start_off = 0
    end_off = 0
    for start, end, run in ranges:
        if start_run is None and start <= idx < end:
            start_run = run
            start_off = idx - start
        if start < idx + len(find) <= end:
            end_run = run
            end_off = idx + len(find) - start
            break
    if start_run is None:
        # Match begins at a run boundary.
        for start, end, run in ranges:
            if start == idx:
                start_run = run
                start_off = 0
                break
    if end_run is None:
        for start, end, run in ranges:
            if end == idx + len(find):
                end_run = run
                end_off = len(run.text)
                break
    if start_run is None or end_run is None:
        warnings.append("文本匹配跨越了不支持的 run 边界，已跳过。")
        return False

    if keep_deleted and replace == "":
        # Keep the original text for review, but mark it as deleted.
        for start, end, run in ranges:
            if end > idx and start < idx + len(find):
                run.font.strike = True
                run.font.color.rgb = RGBColor(0xC0, 0x00, 0x00)
        return True

    prefix = start_run.text[:start_off]
    suffix = end_run.text[end_off:]
    if start_run is end_run:
        start_run.text = prefix + replace + suffix
    else:
        start_run.text = prefix + replace
        # Clear all runs that are fully inside the match.
        clearing = False
        for start, end, run in ranges:
            if run is start_run:
                clearing = True
                continue
            if clearing:
                if run is end_run:
                    run.text = suffix
                    break
                run.text = ""
    if keep_deleted and replace == "":
        start_run.font.strike = True
        start_run.font.color.rgb = RGBColor(0xC0, 0x00, 0x00)
    if highlight:
        start_run.font.highlight_color = WD_COLOR_INDEX.YELLOW
    return True


def _replace_text(
    doc,
    operation: dict[str, Any],
    highlight: bool,
    keep_deleted: bool,
    warnings: list[str],
    paragraph_map: dict[str, Any] | None = None,
) -> dict[str, Any]:
    find = str(operation.get("find") or "")
    replace = str(operation.get("replace") or "")
    if not find:
        raise EngineError("INVALID_ARGS", "replace_text 需要非空 find。")
    occurrence = operation.get("occurrence", "first")
    block_id = operation.get("block_id")

    paragraphs = []
    if block_id:
        paragraph = _get_paragraph(doc, str(block_id), paragraph_map)
        if paragraph is None:
            raise EngineError("BLOCK_NOT_FOUND", f"找不到段落 {block_id}。")
        paragraphs = [paragraph]
    else:
        paragraphs = list(doc.paragraphs)

    target = None
    before = ""
    for paragraph in paragraphs:
        if find in paragraph.text:
            target = paragraph
            before = paragraph.text
            break
    if target is None:
        raise EngineError(
            "TEXT_NOT_FOUND",
            f"找不到要替换的文本: {find[:80]}",
            hint="先用 read 获取 block_id，或提供更精确的上下文。",
        )

    count = 0
    if occurrence == "all":
        # Bound the loop to avoid pathological matches.
        for _ in range(1000):
            if not _replace_once(target, find, replace, highlight, keep_deleted, warnings):
                break
            count += 1
    else:
        if _replace_once(target, find, replace, highlight, keep_deleted, warnings):
            count = 1
    if count == 0:
        raise EngineError("TEXT_NOT_FOUND", f"无法替换文本: {find[:80]}")

    after = target.text
    return {
        "op": "replace_text",
        "block_id": block_id or "",
        "find": find,
        "replace": replace,
        "before": before,
        "after": after,
        "count": count,
    }


def _insert_paragraph(
    doc,
    operation: dict[str, Any],
    highlight: bool,
    before: bool = False,
    paragraph_map: dict[str, Any] | None = None,
) -> dict[str, Any]:
    block_id = str(operation.get("block_id") or "")
    target = _get_paragraph(doc, block_id, paragraph_map)
    if target is None:
        raise EngineError("BLOCK_NOT_FOUND", f"找不到段落 {block_id}。")
    text = str(operation.get("text") or "")
    style = operation.get("style")
    paragraph = doc.add_paragraph()
    _set_style(paragraph, str(style) if style else None)
    run = paragraph.add_run(text)
    if highlight:
        run.font.highlight_color = WD_COLOR_INDEX.YELLOW
    if before:
        target._p.addprevious(paragraph._p)
    else:
        target._p.addnext(paragraph._p)
    return {
        "op": "insert_paragraph_before" if before else "insert_paragraph_after",
        "block_id": block_id,
        "text": text,
    }


def _renumber_following(
    element,
    expected: int,
    parent,
    highlight: bool,
    warnings: list[str],
) -> list[dict[str, Any]]:
    """Renumber consecutive (n) / （n） paragraphs after a deleted item."""
    renumbered: list[dict[str, Any]] = []
    el = element
    while el is not None and el.tag == qn("w:p"):
        paragraph = Paragraph(el, parent)
        text = paragraph.text
        if not text.strip():
            el = el.getnext()
            continue
        match = _NUMBERED_RE.match(text)
        if not match:
            break
        old = int(match.group(2))
        if old != expected:
            old_token = f"{match.group(1)}{match.group(2)}{match.group(3)}"
            new_token = f"{match.group(1)}{expected}{match.group(3)}"
            replaced = _replace_once(
                paragraph, old_token, new_token, highlight, False, warnings
            )
            if not replaced:
                # Fallback for numbers split across runs; this may drop
                # character-level formatting in that one paragraph.
                paragraph.text = text.replace(old_token, new_token, 1)
                warnings.append(
                    f"自动编号：段落 {paragraph.text[:30]!r} 的编号跨 run，"
                    "已用纯文本方式重编号。"
                )
            renumbered.append(
                {"old": old, "new": expected, "text": paragraph.text}
            )
        expected += 1
        el = el.getnext()
    return renumbered


def _delete_block(
    doc,
    operation: dict[str, Any],
    keep_deleted: bool,
    warnings: list[str],
    paragraph_map: dict[str, Any] | None = None,
    table_map: dict[str, Any] | None = None,
    highlight: bool = False,
) -> dict[str, Any]:
    block_id = str(operation.get("block_id") or "")
    paragraph = _get_paragraph(doc, block_id, paragraph_map)
    if paragraph is not None:
        before = paragraph.text
        next_el = paragraph._p.getnext()
        number_match = _NUMBERED_RE.match(before)
        deleted_number = int(number_match.group(2)) if number_match else None
        if keep_deleted:
            _mark_deleted(paragraph)
        else:
            paragraph._p.getparent().remove(paragraph._p)
        renumbered: list[dict[str, Any]] = []
        if not keep_deleted and deleted_number is not None:
            renumbered = _renumber_following(
                next_el,
                deleted_number,
                paragraph._parent,
                highlight,
                warnings,
            )
        return {
            "op": "delete_block",
            "block_id": block_id,
            "before": before,
            "renumbered": renumbered,
        }

    table = _get_table(doc, block_id, table_map)
    if table is not None:
        if keep_deleted:
            warnings.append("keep_deleted 对表格不生效，表格已直接删除。")
        table._tbl.getparent().remove(table._tbl)
        return {"op": "delete_block", "block_id": block_id, "before": "[table]"}

    raise EngineError("BLOCK_NOT_FOUND", f"找不到 block {block_id}。")


def _set_table_cell(
    doc,
    operation: dict[str, Any],
    highlight: bool,
    table_map: dict[str, Any] | None = None,
) -> dict[str, Any]:
    table = _get_table(doc, str(operation.get("table_id") or ""), table_map)
    if table is None:
        raise EngineError("BLOCK_NOT_FOUND", f"找不到表格 {operation.get('table_id')}。")
    try:
        row = int(operation.get("row"))
        col = int(operation.get("col"))
    except (TypeError, ValueError) as exc:
        raise EngineError("INVALID_ARGS", "set_table_cell 需要整数 row/col。") from exc
    try:
        cell = table.cell(row, col)
    except Exception as exc:
        raise EngineError("INVALID_ARGS", f"表格坐标越界: {row},{col}") from exc
    before = cell.text
    cell.text = str(operation.get("value") or "")
    if highlight:
        for paragraph in cell.paragraphs:
            _highlight_paragraph(paragraph)
    return {
        "op": "set_table_cell",
        "table_id": operation.get("table_id"),
        "row": row,
        "col": col,
        "before": before,
        "after": cell.text,
    }


_NS_A = "http://schemas.openxmlformats.org/drawingml/2006/main"
_NS_V = "urn:schemas-microsoft-com:vml"


def _iter_image_nodes(doc):
    """Yield (image_id, image_node) matching the reader's img_001 ordering."""
    seq = 0
    for p in doc.paragraphs:
        for node in p._p.iter():
            if node.tag in (f"{{{_NS_A}}}blip", f"{{{_NS_V}}}imagedata"):
                seq += 1
                yield f"img_{seq:03d}", node


def _delete_image(doc, operation: dict[str, Any]) -> dict[str, Any]:
    image_id = str(operation.get("image_id") or "")
    if not image_id:
        raise EngineError("INVALID_ARGS", "delete_image 需要 image_id。")
    for current_id, node in _iter_image_nodes(doc):
        if current_id == image_id:
            # Remove the whole drawing/picture, not just the blip reference.
            target = node
            while target is not None and target.tag not in (
                qn("w:drawing"),
                qn("w:pict"),
            ):
                target = target.getparent()
            if target is not None and target.getparent() is not None:
                target.getparent().remove(target)
            else:
                parent = node.getparent()
                if parent is not None:
                    parent.remove(node)
            return {"op": "delete_image", "image_id": image_id}
    raise EngineError("BLOCK_NOT_FOUND", f"找不到图片 {image_id}。")


def _insert_image(
    doc,
    operation: dict[str, Any],
    base_dir: Path,
    highlight: bool,
    paragraph_map: dict[str, Any] | None = None,
) -> dict[str, Any]:
    block_id = str(operation.get("block_id") or "")
    target = _get_paragraph(doc, block_id, paragraph_map)
    if target is None:
        raise EngineError("BLOCK_NOT_FOUND", f"找不到段落 {block_id}。")
    path_value = operation.get("path")
    if not isinstance(path_value, str) or not path_value.strip():
        raise EngineError("INVALID_ARGS", "insert_image_after 需要 path。")
    image_path = resolve_path(path_value, base_dir)
    if not image_path.is_file():
        raise EngineError("FILE_NOT_FOUND", f"图片不存在: {image_path}")
    paragraph = doc.add_paragraph()
    run = paragraph.add_run()
    width = operation.get("width_cm")
    if width is not None:
        run.add_picture(str(image_path), width=Cm(float(width)))
    else:
        run.add_picture(str(image_path))
    target._p.addnext(paragraph._p)
    caption = operation.get("caption")
    if isinstance(caption, str) and caption.strip():
        cap = doc.add_paragraph(caption.strip())
        _set_style(cap, "Caption")
        if highlight:
            _highlight_paragraph(cap)
        paragraph._p.addnext(cap._p)
    return {
        "op": "insert_image_after",
        "block_id": block_id,
        "path": str(image_path),
        "caption": caption or "",
    }


def _center_tables(
    doc,
    operation: dict[str, Any],
    table_map: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Center table contents horizontally and vertically.

    - table.alignment centers the table block on the page;
    - cell.vertical_alignment centers content top/bottom;
    - paragraph.alignment centers text left/right.
    """
    requested = operation.get("table_ids")
    tables = []
    if isinstance(requested, list) and requested:
        for table_id in requested:
            table = _get_table(doc, str(table_id), table_map)
            if table is None:
                raise EngineError("BLOCK_NOT_FOUND", f"找不到表格 {table_id}。")
            tables.append(table)
    else:
        tables = list(doc.tables)

    for table in tables:
        try:
            table.alignment = WD_TABLE_ALIGNMENT.CENTER
        except Exception:
            pass
        for row in table.rows:
            for cell in row.cells:
                try:
                    cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
                except Exception:
                    pass
                for paragraph in cell.paragraphs:
                    paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER

    return {"op": "center_tables", "tables": len(tables)}


def _insert_table_row(
    doc,
    operation: dict[str, Any],
    table_map: dict[str, Any] | None = None,
) -> dict[str, Any]:
    table = _get_table(doc, str(operation.get("table_id") or ""), table_map)
    if table is None:
        raise EngineError("BLOCK_NOT_FOUND", f"找不到表格 {operation.get('table_id')}。")
    values = operation.get("values")
    row = table.add_row()
    if isinstance(values, list):
        for idx, value in enumerate(values):
            if idx < len(row.cells):
                row.cells[idx].text = str(value)
    return {
        "op": "insert_table_row",
        "table_id": operation.get("table_id"),
        "row": len(table.rows) - 1,
    }


def _delete_table_row(
    doc,
    operation: dict[str, Any],
    table_map: dict[str, Any] | None = None,
) -> dict[str, Any]:
    table = _get_table(doc, str(operation.get("table_id") or ""), table_map)
    if table is None:
        raise EngineError("BLOCK_NOT_FOUND", f"找不到表格 {operation.get('table_id')}。")
    try:
        row = int(operation.get("row"))
    except (TypeError, ValueError) as exc:
        raise EngineError("INVALID_ARGS", "delete_table_row 需要整数 row。") from exc
    if row < 0 or row >= len(table.rows):
        raise EngineError("INVALID_ARGS", f"表格行越界: {row}")
    tr = table.rows[row]._tr
    tr.getparent().remove(tr)
    return {"op": "delete_table_row", "table_id": operation.get("table_id"), "row": row}


def _validate_output(path: Path) -> None:
    try:
        Document(str(path))
    except Exception as exc:
        raise EngineError(
            "VALIDATION_FAILED",
            f"写出的 docx 无法重新打开: {exc}",
            hint="原文件未被修改；请重试或换一个输出路径。",
        ) from exc


def _write_changes(output: Path, changes: list[dict[str, Any]]) -> tuple[str, str]:
    json_path = output.with_name(f"{output.stem}.changes.json")
    md_path = output.with_name(f"{output.stem}.changes.md")
    write_json(json_path, {"changes": changes, "created_at": now_iso()})
    lines = ["# Word 变更记录", "", f"- 输出: `{output}`", ""]
    for idx, change in enumerate(changes, 1):
        lines.append(f"## {idx}. {change.get('op')}")
        if change.get("block_id"):
            lines.append(f"- block: `{change['block_id']}`")
        if change.get("table_id"):
            lines.append(f"- table: `{change['table_id']}`")
        if change.get("before") is not None:
            lines.append("")
            lines.append("**修改前**")
            lines.append("")
            lines.append("```text")
            lines.append(str(change.get("before", "")))
            lines.append("```")
        if change.get("after") is not None:
            lines.append("")
            lines.append("**修改后**")
            lines.append("")
            lines.append("```text")
            lines.append(str(change.get("after", "")))
            lines.append("```")
        lines.append("")
    md_path.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    return str(json_path), str(md_path)


def edit_word(request: dict[str, Any]) -> dict[str, Any]:
    source_value = request.get("source") or request.get("path")
    if not isinstance(source_value, str) or not source_value.strip():
        raise EngineError("INVALID_REQUEST", "edit 缺少 source 参数。")
    source = resolve_path(source_value, request.get("base_dir"))
    if not source.is_file():
        raise EngineError("FILE_NOT_FOUND", f"文件不存在: {source}")

    options = request.get("options") or {}
    if not isinstance(options, dict):
        options = {}
    highlight_name = str(options.get("highlight") or "visual").lower()
    if highlight_name == "track_changes":
        raise EngineError(
            "UNSUPPORTED_OPTION",
            "MVP 不支持真正的 Word 修订（track changes）。",
            hint="请使用 highlight=visual；真正的修订需要后续 XML/LibreOffice UNO 支持。",
        )
    highlight = highlight_name == "visual"
    keep_deleted = options.get("keep_deleted") is True

    in_place = request.get("in_place") is True
    if in_place and source.suffix.lower() != ".docx":
        raise EngineError(
            "UNSUPPORTED_OPTION",
            "只能对 .docx 做原地修改；.doc 请输出新 docx。",
        )

    output_value = request.get("output")
    if in_place:
        output = source
    elif isinstance(output_value, str) and output_value.strip():
        output = resolve_path(output_value, request.get("base_dir"))
    else:
        output = source.with_name(f"{source.stem}.edited.docx")
        if output.exists():
            output = unique_path(output)
    if output.suffix.lower() != ".docx":
        raise EngineError(
            "UNSUPPORTED_OUTPUT_FORMAT",
            "当前引擎只输出 .docx。",
            hint="请把 output 改成 .docx。",
        )
    if not in_place and output.resolve() == source.resolve():
        raise EngineError(
            "INVALID_ARGS",
            "output 不能等于 source；如需覆盖请显式使用 in_place=true。",
        )
    ensure_dir(output.parent)

    source_hash = sha256_file(source)
    expected_hash = request.get("document_hash")
    if isinstance(expected_hash, str) and expected_hash and expected_hash != source_hash:
        raise EngineError(
            "STALE_DOCUMENT",
            "文档已被修改，document_hash 不匹配。",
            hint="请重新调用 read，再基于新的 block_id 编辑。",
        )

    temp_dir = Path(tempfile.mkdtemp(prefix="office_word_edit_"))
    docx_source = source
    converted_from = None
    try:
        if source.suffix.lower() == ".doc":
            docx_source = convert_doc_to_docx(source, temp_dir)
            converted_from = "doc"
        try:
            doc = Document(str(docx_source))
        except Exception as exc:
            raise EngineError(
                "PARSE_FAILED",
                f"无法解析 Word 文档: {exc}",
                hint="确认文件未损坏、未加密。",
            ) from exc

        operations = request.get("operations")
        if not isinstance(operations, list) or not operations:
            raise EngineError("INVALID_REQUEST", "edit 需要非空 operations 数组。")

        changes: list[dict[str, Any]] = []
        warnings: list[str] = []
        base_dir = source.parent
        # Snapshot block IDs before mutating.  Inserting/deleting paragraphs
        # shifts list indices, so later operations must use the original
        # paragraph/table objects rather than re-indexing doc.paragraphs.
        paragraph_map = {f"p{i}": p for i, p in enumerate(doc.paragraphs)}
        table_map = {f"t{i}": t for i, t in enumerate(doc.tables)}
        for operation in operations:
            if not isinstance(operation, dict):
                continue
            op = str(operation.get("op") or "").lower()
            if op == "replace_text":
                changes.append(
                    _replace_text(
                        doc,
                        operation,
                        highlight,
                        keep_deleted,
                        warnings,
                        paragraph_map=paragraph_map,
                    )
                )
            elif op == "insert_paragraph_after":
                changes.append(
                    _insert_paragraph(
                        doc,
                        operation,
                        highlight,
                        before=False,
                        paragraph_map=paragraph_map,
                    )
                )
            elif op == "insert_paragraph_before":
                changes.append(
                    _insert_paragraph(
                        doc,
                        operation,
                        highlight,
                        before=True,
                        paragraph_map=paragraph_map,
                    )
                )
            elif op == "delete_block":
                changes.append(
                    _delete_block(
                        doc,
                        operation,
                        keep_deleted,
                        warnings,
                        paragraph_map=paragraph_map,
                        table_map=table_map,
                        highlight=highlight,
                    )
                )
            elif op == "set_table_cell":
                changes.append(
                    _set_table_cell(
                        doc, operation, highlight, table_map=table_map
                    )
                )
            elif op == "insert_image_after":
                changes.append(
                    _insert_image(
                        doc,
                        operation,
                        base_dir,
                        highlight,
                        paragraph_map=paragraph_map,
                    )
                )
            elif op == "center_tables":
                changes.append(
                    _center_tables(doc, operation, table_map=table_map)
                )
            elif op == "delete_image":
                changes.append(_delete_image(doc, operation))
            elif op == "insert_table_row":
                changes.append(
                    _insert_table_row(doc, operation, table_map=table_map)
                )
            elif op == "delete_table_row":
                changes.append(
                    _delete_table_row(doc, operation, table_map=table_map)
                )
            else:
                raise EngineError(
                    "UNSUPPORTED_OPERATION",
                    f"不支持的编辑操作: {op}",
                    hint="支持: replace_text, insert_paragraph_after/before, delete_block, set_table_cell, insert_image_after, delete_image, insert_table_row, delete_table_row。",
                )

        # Word needs a body paragraph; keep an empty one if an operation
        # deleted everything.
        if not doc.paragraphs:
            doc.add_paragraph("")

        tmp = output.parent / f".{output.stem}.tmp-{uuid.uuid4().hex[:8]}.docx"
        backup: Path | None = None
        try:
            doc.save(str(tmp))
            _validate_output(tmp)
            if in_place:
                backup = source.with_name(
                    f"{source.stem}.bak-{timestamp_slug()}{source.suffix}"
                )
                shutil.copy2(source, backup)
                os.replace(tmp, source)
                output = source
            else:
                atomic_write_file(tmp, output)
                cleanup_old_backups(output.parent)
        finally:
            tmp.unlink(missing_ok=True)

        changes_json, changes_md = _write_changes(output, changes)
        return ok(
            action="edit",
            source=str(source),
            output=str(output),
            output_format="docx",
            converted_from=converted_from,
            document_hash=sha256_file(output),
            source_hash=source_hash,
            changes=changes,
            changes_json=changes_json,
            changes_md=changes_md,
            warnings=warnings,
            backup=str(backup) if backup else None,
            in_place=in_place,
        )
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def file_operation(request: dict[str, Any]) -> dict[str, Any]:
    path_value = request.get("path")
    if not isinstance(path_value, str) or not path_value.strip():
        raise EngineError("INVALID_REQUEST", "file 缺少 path 参数。")
    path = resolve_path(path_value, request.get("base_dir"))
    operation = str(request.get("operation") or "info").lower()

    if operation == "info":
        if not path.exists():
            raise EngineError("FILE_NOT_FOUND", f"文件不存在: {path}")
        info: dict[str, Any] = {
            "action": "file",
            "operation": "info",
            "path": str(path),
            "exists": True,
            "is_file": path.is_file(),
            "is_dir": path.is_dir(),
            "size": path.stat().st_size,
            "mtime": path.stat().st_mtime,
        }
        if path.is_file():
            info["sha256"] = sha256_file(path)
            if path.suffix.lower() in (".docx", ".docm"):
                import zipfile

                try:
                    with zipfile.ZipFile(path) as zf:
                        info["docx_zip_ok"] = "word/document.xml" in zf.namelist()
                except Exception:
                    info["docx_zip_ok"] = False
        return ok(**info)

    if operation == "delete":
        if not path.is_file():
            raise EngineError("FILE_NOT_FOUND", f"文件不存在: {path}")
        mode = str(request.get("mode") or "trash").lower()
        if mode == "permanent":
            if request.get("confirm") is not True:
                raise EngineError(
                    "CONFIRMATION_REQUIRED",
                    "永久删除需要 confirm=true。",
                    hint="默认使用 mode=trash 保留可恢复副本。",
                )
            path.unlink()
            return ok(action="file", operation="delete", path=str(path), mode="permanent")
        trashed = path.with_name(f"{path.name}.deleted-{timestamp_slug()}")
        trashed = unique_path(trashed)
        os.replace(path, trashed)
        return ok(
            action="file",
            operation="delete",
            path=str(path),
            mode="trash",
            trashed_to=str(trashed),
        )

    if operation in ("copy", "move"):
        if not path.is_file():
            raise EngineError("FILE_NOT_FOUND", f"文件不存在: {path}")
        dest_value = request.get("dest") or request.get("destination")
        if not isinstance(dest_value, str) or not dest_value.strip():
            raise EngineError("INVALID_REQUEST", f"{operation} 需要 dest 参数。")
        dest = resolve_path(dest_value, request.get("base_dir"))
        if dest.exists() and request.get("overwrite") is not True:
            dest = unique_path(dest)
        ensure_dir(dest.parent)
        if operation == "copy":
            shutil.copy2(path, dest)
        else:
            shutil.move(str(path), str(dest))
        return ok(
            action="file",
            operation=operation,
            path=str(path),
            dest=str(dest),
        )

    raise EngineError(
        "UNSUPPORTED_OPERATION",
        f"不支持的文件操作: {operation}",
        hint="支持: info, delete, copy, move。",
    )
