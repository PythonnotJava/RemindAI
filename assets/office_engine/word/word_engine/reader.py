"""DOCX reader: blocks, Markdown, images, captions and stable block IDs."""

from __future__ import annotations

import json
import os
import re
import shutil
import tempfile
import uuid
import zipfile
from io import BytesIO
from pathlib import Path
from typing import Any

from docx import Document
from docx.oxml.ns import qn
from lxml import etree
from PIL import Image

from .legacy import convert_doc_to_docx
from .protocol import ENGINE_NAME, ENGINE_VERSION, EngineError, ok
from .utils import (
    ensure_dir,
    now_iso,
    publish_dir,
    resolve_path,
    sanitize_filename,
    sha256_bytes,
    sha256_file,
    write_json,
)

Image.MAX_IMAGE_PIXELS = 50_000_000

_NS_W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
_NS_A = "http://schemas.openxmlformats.org/drawingml/2006/main"
_NS_R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
_NS_WP = "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
_NS_V = "urn:schemas-microsoft-com:vml"
_NS_O = "urn:schemas-microsoft-com:office:office"
_NS_MC = "http://schemas.openxmlformats.org/markup-compatibility/2006"
_NS_M = "http://schemas.openxmlformats.org/officeDocument/2006/math"

_CAPTION_RE = re.compile(
    r"^\s*((?:图|圖|Figure|Fig\.?)\s*\d+(?:[\-.]\d+)*)",
    re.IGNORECASE,
)


def _w(tag: str) -> str:
    return f"{{{_NS_W}}}{tag}"


def _caption_label(text: str) -> str | None:
    m = _CAPTION_RE.match(text or "")
    if not m:
        return None
    return re.sub(r"\s+", "", m.group(1))


def _heading_level(paragraph) -> int | None:
    style = (paragraph.style.name if paragraph.style is not None else "") or ""
    m = re.match(r"^Heading\s*(\d+)$", style, re.IGNORECASE)
    if m:
        return max(1, min(6, int(m.group(1))))
    if style.lower() == "title":
        return 1
    if style.lower() == "subtitle":
        return 2

    # Many Chinese papers use Normal style + manual numbering (1.1 背景).
    # Treat short numbered lines as headings so the Markdown keeps structure.
    text = (paragraph.text or "").strip()
    if text and len(text) <= 40 and not re.search(r"[。；，,;]", text):
        m = re.match(r"^(\d+(?:\.\d+)*)\s*([^\d\s].{0,38})$", text)
        if m:
            return max(1, min(6, m.group(1).count(".") + 1))
    return None


def _list_kind(paragraph) -> str | None:
    style = (paragraph.style.name if paragraph.style is not None else "") or ""
    low = style.lower()
    if "list bullet" in low or "list paragraph" in low:
        # List Paragraph with numPr is usually a bullet; numbering detection is
        # out of scope for the MVP, but mark it so Markdown keeps structure.
        return "bullet"
    if "list number" in low:
        return "number"
    return None


def _paragraph_text(paragraph) -> str:
    try:
        return paragraph.text.replace("\r\n", "\n").replace("\r", "\n")
    except Exception:
        return ""


def _table_rows(table) -> list[list[str]]:
    rows: list[list[str]] = []
    for row in table.rows:
        values: list[str] = []
        for cell in row.cells:
            values.append(cell.text.replace("\r\n", "\n").replace("\r", "\n").strip())
        rows.append(values)
    return rows


def _table_has_spans(table) -> bool:
    for row in table.rows:
        for cell in row.cells:
            tc_pr = cell._tc.tcPr
            if tc_pr is None:
                continue
            if tc_pr.find(qn("w:gridSpan")) is not None:
                return True
            if tc_pr.find(qn("w:vMerge")) is not None:
                return True
    return False


def _resolve_rel(doc, rid: str):
    try:
        return doc.part.rels[rid]
    except KeyError:
        return None


def _image_ext(partname: str | None, blob: bytes) -> str:
    if partname:
        suffix = Path(str(partname)).suffix.lower()
        if suffix:
            return suffix
    if blob.startswith(b"\x89PNG"):
        return ".png"
    if blob.startswith(b"\xff\xd8"):
        return ".jpg"
    if blob.startswith(b"GIF8"):
        return ".gif"
    if blob.startswith(b"BM"):
        return ".bmp"
    if blob.startswith(b"RIFF") and b"WEBP" in blob[:16]:
        return ".webp"
    return ".bin"


def _collect_images_from_paragraph(doc, p_el, anchor_id: str) -> list[dict[str, Any]]:
    """Collect embedded images in document order from a paragraph element."""
    found: list[dict[str, Any]] = []

    # mc:AlternateContent often carries the same picture twice: a modern
    # DrawingML branch (Choice) and a legacy VML/bitmap fallback (Fallback).
    # Prefer the Choice branch so one figure does not become two images.
    fallback_nodes: set[Any] = set()
    for alt in p_el.findall(f".//{{{_NS_MC}}}AlternateContent"):
        if alt.find(f"{{{_NS_MC}}}Choice") is not None:
            for node in alt.findall(f".//{{{_NS_MC}}}Fallback//{{{_NS_A}}}blip"):
                fallback_nodes.add(node)
            for node in alt.findall(f".//{{{_NS_MC}}}Fallback//{{{_NS_V}}}imagedata"):
                fallback_nodes.add(node)

    # DrawingML images (modern Word)
    for blip in p_el.findall(f".//{{{_NS_A}}}blip"):
        if blip in fallback_nodes:
            continue
        rid = blip.get(f"{{{_NS_R}}}embed") or blip.get(f"{{{_NS_R}}}link")
        if not rid:
            continue
        rel = _resolve_rel(doc, rid)
        if rel is None:
            continue
        if getattr(rel, "is_external", False):
            found.append(
                {
                    "external": True,
                    "rel_id": rid,
                    "target": getattr(rel, "target_ref", ""),
                    "anchor_paragraph_id": anchor_id,
                    "alt": "",
                }
            )
            continue
        try:
            part = rel.target_part
            blob = part.blob
            partname = str(part.partname)
        except Exception:
            continue
        doc_pr = p_el.find(f".//{{{_NS_WP}}}docPr")
        alt = ""
        name = ""
        if doc_pr is not None:
            alt = (doc_pr.get("descr") or "").strip()
            name = (doc_pr.get("name") or "").strip()
        found.append(
            {
                "external": False,
                "rel_id": rid,
                "blob": blob,
                "partname": partname,
                "ext": _image_ext(partname, blob),
                "alt": alt or name,
                "anchor_paragraph_id": anchor_id,
            }
        )

    # VML images (older Word / some WPS output)
    for imagedata in p_el.findall(f".//{{{_NS_V}}}imagedata"):
        if imagedata in fallback_nodes:
            continue
        rid = imagedata.get(f"{{{_NS_R}}}id")
        if not rid:
            continue
        rel = _resolve_rel(doc, rid)
        if rel is None:
            continue
        if getattr(rel, "is_external", False):
            found.append(
                {
                    "external": True,
                    "rel_id": rid,
                    "target": getattr(rel, "target_ref", ""),
                    "anchor_paragraph_id": anchor_id,
                    "alt": (imagedata.get(f"{{{_NS_O}}}title") or "").strip(),
                }
            )
            continue
        try:
            part = rel.target_part
            blob = part.blob
            partname = str(part.partname)
        except Exception:
            continue
        found.append(
            {
                "external": False,
                "rel_id": rid,
                "blob": blob,
                "partname": partname,
                "ext": _image_ext(partname, blob),
                "alt": (imagedata.get(f"{{{_NS_O}}}title") or "").strip(),
                "anchor_paragraph_id": anchor_id,
            }
        )

    return found


def _comment_refs(p_el) -> list[str]:
    """Comment IDs referenced by a paragraph.

    Word usually puts a w:commentReference at the end of the range, but some
    producers only emit w:commentRangeStart/End.  Collect both so comments
    anchored to empty paragraphs or table cells are not lost.
    """
    ids: list[str] = []
    for tag in ("commentReference", "commentRangeStart"):
        for ref in p_el.findall(f".//{{{_NS_W}}}{tag}"):
            cid = ref.get(f"{{{_NS_W}}}id")
            if cid and cid not in ids:
                ids.append(cid)
    return ids


def _load_comments(docx_path: Path, warnings: list[str]) -> list[dict[str, Any]]:
    """Parse word/comments.xml.  python-docx has no comments API."""
    try:
        with zipfile.ZipFile(str(docx_path)) as zf:
            if "word/comments.xml" not in zf.namelist():
                return []
            root = etree.fromstring(zf.read("word/comments.xml"))
    except Exception as exc:
        warnings.append(f"读取 Word 批注失败: {exc}")
        return []

    comments: list[dict[str, Any]] = []
    for node in root.findall(f"{{{_NS_W}}}comment"):
        cid = node.get(f"{{{_NS_W}}}id") or ""
        raw_text = "".join(
            t.text or "" for t in node.findall(f".//{{{_NS_W}}}t")
        )
        # Word often splits a sentence into many w:t runs/lines; normalize so
        # the Agent sees "启停决策" instead of "启\n停决策".
        text = re.sub(r"\s+", " ", raw_text).strip()
        comments.append(
            {
                "id": cid,
                "author": node.get(f"{{{_NS_W}}}author") or "",
                "initials": node.get(f"{{{_NS_W}}}initials") or "",
                "date": node.get(f"{{{_NS_W}}}date") or "",
                "text": text,
                "anchor_block_id": "",
                "anchor_text": "",
            }
        )
    return comments


def _render_comments(comments: list[dict[str, Any]]) -> str:
    if not comments:
        return ""
    lines = ["## Word 批注"]
    for c in comments:
        author = c.get("author") or "未知作者"
        date = c.get("date") or ""
        suffix = f"，{date}" if date else ""
        lines.append(f"- **批注 {c.get('id')}**（{author}{suffix}）：{c.get('text', '')}")
        anchor = (c.get("anchor_text") or "").replace("\n", " ").strip()
        if anchor:
            lines.append(f"  - 锚点 `{c.get('anchor_block_id')}`：{anchor[:80]}")
    return "\n".join(lines)


def _textbox_texts(p_el) -> list[str]:
    values: list[str] = []
    for box in p_el.findall(f".//{{{_NS_W}}}txbxContent"):
        text = "".join(t.text or "" for t in box.findall(f".//{{{_NS_W}}}t"))
        text = text.strip()
        if text:
            values.append(text)
    return values


def _normalize_image(
    blob: bytes,
    ext: str,
    label: str,
    seq: int,
    images_dir: Path,
    dedupe: dict[str, str],
    warnings: list[str],
) -> tuple[str, int, int, int]:
    """Save a normalized image, returning (relative path, width, height, size)."""
    digest = sha256_bytes(blob)
    if digest in dedupe:
        existing = images_dir.parent / dedupe[digest]
        try:
            with Image.open(existing) as im:
                return dedupe[digest], im.width, im.height, existing.stat().st_size
        except Exception:
            return dedupe[digest], 0, 0, existing.stat().st_size if existing.exists() else 0

    stem = sanitize_filename(label, f"图{seq:03d}")
    width = height = 0
    try:
        with Image.open(BytesIO(blob)) as im:
            im.load()
            width, height = im.width, im.height
            if im.mode not in ("RGB", "RGBA"):
                im = im.convert("RGBA" if "A" in im.getbands() else "RGB")
            im.thumbnail((2048, 2048), Image.LANCZOS)
            prefer_png = ext.lower() in (
                ".png",
                ".gif",
                ".bmp",
                ".tif",
                ".tiff",
                ".webp",
            ) or im.mode == "RGBA"
            if prefer_png:
                suffix = ".png"
                target = images_dir / f"{stem}{suffix}"
                if target.exists():
                    target = images_dir / f"{stem}-{seq}{suffix}"
                im.save(target, "PNG", optimize=True)
            else:
                suffix = ".jpg"
                target = images_dir / f"{stem}{suffix}"
                if target.exists():
                    target = images_dir / f"{stem}-{seq}{suffix}"
                im.convert("RGB").save(target, "JPEG", quality=85, optimize=True)
    except Exception as exc:
        # EMF/WMF/SVG and corrupt images: keep the original bytes rather than
        # silently dropping content.  The host can still show the file.
        warnings.append(f"图片 {label} 无法转换为位图，已保留原格式: {exc}")
        suffix = ext if ext and ext != ".bin" else ".bin"
        target = images_dir / f"{stem}{suffix}"
        if target.exists():
            target = images_dir / f"{stem}-{seq}{suffix}"
        target.write_bytes(blob)
        width = height = 0

    rel = f"images/{target.name}"
    dedupe[digest] = rel
    return rel, width, height, target.stat().st_size


def _render_table(rows: list[list[str]]) -> str:
    if not rows:
        return ""
    width = max(len(r) for r in rows)
    normalized = [r + [""] * (width - len(r)) for r in rows]
    header = normalized[0]
    body = normalized[1:]
    def esc(value: str) -> str:
        return str(value).replace("|", "\\|").replace("\n", "<br>")
    lines = ["| " + " | ".join(esc(v) for v in header) + " |"]
    lines.append("| " + " | ".join("---" for _ in header) + " |")
    for row in body:
        lines.append("| " + " | ".join(esc(v) for v in row) + " |")
    return "\n".join(lines)


def _render_markdown(
    blocks: list[dict[str, Any]],
    text_only: bool,
    max_chars: int,
    comments: list[dict[str, Any]] | None = None,
) -> tuple[str, bool]:
    parts: list[str] = []
    for block in blocks:
        kind = block.get("type")
        if kind == "heading":
            level = int(block.get("level") or 1)
            parts.append("#" * max(1, min(6, level)) + " " + block.get("text", ""))
        elif kind == "paragraph":
            text = block.get("text", "")
            if text:
                parts.append(text)
        elif kind == "textbox":
            text = block.get("text", "")
            if text:
                parts.append(text)
        elif kind == "table":
            table = _render_table(block.get("rows") or [])
            if table:
                parts.append(table)
        elif kind == "image":
            label = block.get("label") or block.get("id") or "图片"
            caption = block.get("caption") or ""
            alt = caption or label
            path = block.get("path") or ""
            if text_only:
                parts.append(f"[{alt}]" if alt else "[图片]")
            else:
                parts.append(f"![{alt}]({path})" if path else f"[{alt}]")
        elif kind == "list_item":
            prefix = "- " if block.get("list") == "bullet" else "1. "
            parts.append(prefix + block.get("text", ""))

    comment_section = _render_comments(comments or [])
    if comment_section:
        parts.append(comment_section)

    text = "\n\n".join(p for p in parts if p is not None)
    truncated = False
    if max_chars and max_chars > 0 and len(text) > max_chars:
        text = text[:max_chars].rstrip() + "\n\n... [内容过大，已截断]"
        truncated = True
    return text, truncated


def _load_docx(path: Path, temp_dir: Path) -> tuple[Path, str | None, str]:
    """Return (docx_path, converted_from_suffix, original_sha256)."""
    suffix = path.suffix.lower()
    original_hash = sha256_file(path)
    if suffix == ".docx":
        return path, None, original_hash
    if suffix == ".doc":
        converted = convert_doc_to_docx(path, temp_dir)
        return converted, "doc", original_hash
    if suffix == ".docm":
        # python-docx can read the OOXML package; macros are ignored.
        return path, "docm", original_hash
    raise EngineError(
        "UNSUPPORTED_FORMAT",
        f"不支持读取 {suffix or '无扩展名'} 文件。",
        hint="当前 Word 引擎支持 .docx 和 .doc（需 LibreOffice）。",
    )


def read_word(request: dict[str, Any]) -> dict[str, Any]:
    path_value = request.get("path") or request.get("source")
    if not isinstance(path_value, str) or not path_value.strip():
        raise EngineError("INVALID_REQUEST", "缺少 path/source 参数。")
    source = resolve_path(path_value, request.get("base_dir"))
    if not source.is_file():
        raise EngineError("FILE_NOT_FOUND", f"文件不存在: {source}")

    options = request.get("options") or {}
    if not isinstance(options, dict):
        options = {}
    max_chars = int(options.get("max_chars") or 100000)
    max_images = int(options.get("max_images") or 200)
    include_images = options.get("include_images", True) is not False
    mode = str(options.get("mode") or "full")

    stem = sanitize_filename(source.stem, "document")
    output_value = request.get("output_dir")
    if isinstance(output_value, str) and output_value.strip():
        output_dir = resolve_path(output_value, request.get("base_dir"))
    else:
        output_dir = Path.cwd() / ".toolshell" / "office_engine" / stem

    tmp_parent = output_dir.parent
    ensure_dir(tmp_parent)
    work_tmp = Path(tempfile.mkdtemp(prefix=f".{stem}.src-", dir=str(tmp_parent)))
    output_tmp = Path(tempfile.mkdtemp(prefix=f".{stem}.out-", dir=str(tmp_parent)))
    warnings: list[str] = []
    try:
        docx_path, converted_from, source_hash = _load_docx(source, work_tmp)
        try:
            doc = Document(str(docx_path))
        except Exception as exc:
            raise EngineError(
                "PARSE_FAILED",
                f"无法解析 Word 文档: {exc}",
                hint="确认文件未损坏、未加密；如为 .doc 请安装 LibreOffice。",
            ) from exc

        images_dir = output_tmp / "images"
        ensure_dir(images_dir)

        paragraphs = list(doc.paragraphs)
        tables = list(doc.tables)
        para_index = {id(p._p): i for i, p in enumerate(paragraphs)}
        table_index = {id(t._tbl): i for i, t in enumerate(tables)}

        blocks: list[dict[str, Any]] = []
        image_records: list[dict[str, Any]] = []
        image_seq = 0
        equation_count = 0

        for child in doc.element.body.iterchildren():
            if child.tag == qn("w:p"):
                idx = para_index.get(id(child))
                if idx is None:
                    continue
                paragraph = paragraphs[idx]
                block_id = f"p{idx}"
                text = _paragraph_text(paragraph)
                heading = _heading_level(paragraph)
                list_kind = _list_kind(paragraph)
                equation_count += len(
                    child.findall(f".//{{{_NS_M}}}oMath")
                )

                comment_ids = _comment_refs(child)
                if text or comment_ids:
                    if heading:
                        block = {
                            "id": block_id,
                            "type": "heading",
                            "level": heading,
                            "text": text,
                            "style": paragraph.style.name if paragraph.style else "",
                        }
                    elif list_kind:
                        block = {
                            "id": block_id,
                            "type": "list_item",
                            "list": list_kind,
                            "text": text,
                            "style": paragraph.style.name if paragraph.style else "",
                        }
                    else:
                        block = {
                            "id": block_id,
                            "type": "paragraph",
                            "text": text,
                            "style": paragraph.style.name if paragraph.style else "",
                        }
                    if comment_ids:
                        block["comment_ids"] = comment_ids
                    blocks.append(block)

                # Text boxes are not included in paragraph.text in python-docx.
                for box_text in _textbox_texts(child):
                    blocks.append(
                        {
                            "id": f"tb{len(blocks)}",
                            "type": "textbox",
                            "text": box_text,
                            "anchor_paragraph_id": block_id,
                        }
                    )
                    warnings.append(f"段落 {block_id} 含文本框，已按普通段落提取。")

                if include_images:
                    for item in _collect_images_from_paragraph(doc, child, block_id):
                        if item.get("external"):
                            warnings.append(
                                f"图片为外部链接，未下载: {item.get('target', '')}"
                            )
                            continue
                        image_seq += 1
                        image_records.append(
                            {
                                **item,
                                "id": f"img_{image_seq:03d}",
                                "order": image_seq,
                                "anchor_paragraph_id": block_id,
                            }
                        )
                        blocks.append(
                            {
                                "id": f"img_{image_seq:03d}",
                                "type": "image",
                                "anchor_paragraph_id": block_id,
                                "order": image_seq,
                                "label": "",
                                "caption": "",
                                "alt": item.get("alt", ""),
                                "path": "",
                            }
                        )

            elif child.tag == qn("w:tbl"):
                idx = table_index.get(id(child))
                if idx is None:
                    continue
                table = tables[idx]
                equation_count += len(
                    child.findall(f".//{{{_NS_M}}}oMath")
                )
                rows = _table_rows(table)
                block = {
                    "id": f"t{idx}",
                    "type": "table",
                    "rows": rows,
                    "header": True,
                }
                table_comment_ids: list[str] = []
                table_anchor = ""
                for row in table.rows:
                    for cell in row.cells:
                        if not table_anchor and cell.text.strip():
                            table_anchor = cell.text.strip()
                        for cell_paragraph in cell.paragraphs:
                            for cid in _comment_refs(cell_paragraph._p):
                                if cid not in table_comment_ids:
                                    table_comment_ids.append(cid)
                if table_comment_ids:
                    block["comment_ids"] = table_comment_ids
                    block["anchor_text"] = table_anchor
                if _table_has_spans(table):
                    warnings.append(
                        f"表格 t{idx} 含合并单元格，Markdown 可能无法完整表达。"
                    )
                blocks.append(block)

        if equation_count:
            warnings.append(
                f"检测到 {equation_count} 个公式，当前版本未提取公式内容（OMML）。"
            )

        comments = _load_comments(docx_path, warnings)
        if comments:
            by_id = {c["id"]: c for c in comments}
            for block in blocks:
                for cid in block.get("comment_ids", []) or []:
                    comment = by_id.get(str(cid))
                    if comment is not None:
                        comment["anchor_block_id"] = block.get("id", "")
                        comment["anchor_text"] = (
                            block.get("anchor_text") or block.get("text", "")
                        )
            for comment in comments:
                if not comment.get("anchor_block_id"):
                    warnings.append(
                        f"批注 {comment.get('id')} 未找到锚点，可能是页眉/页脚或表格内批注。"
                    )

        # Assign captions/labels to images.  Prefer the next 1-2 blocks, then
        # the previous 1-2 blocks; this covers captions above and below.
        image_blocks = [b for b in blocks if b.get("type") == "image"]
        for image_block in image_blocks:
            try:
                pos = blocks.index(image_block)
            except ValueError:
                continue
            caption = ""
            for offset in (1, 2, -1, -2):
                idx = pos + offset
                if idx < 0 or idx >= len(blocks):
                    continue
                candidate = blocks[idx]
                if candidate.get("type") not in ("paragraph", "heading"):
                    continue
                text = candidate.get("text", "")
                if not text:
                    continue
                style = str(candidate.get("style") or "").lower()
                if "caption" in style or _caption_label(text):
                    caption = text
                    break
            image_block["caption"] = caption
            label = _caption_label(caption) or _caption_label(image_block.get("alt", ""))
            image_block["label"] = label or ""
            if not caption and not label:
                image_block["label"] = f"图{image_block['order']:03d}"

        # Save images and fill paths.  Deduplicate identical bytes.
        dedupe: dict[str, str] = {}
        for record, block in zip(image_records, image_blocks):
            label = block.get("label") or f"图{record['order']:03d}"
            rel, width, height, size = _normalize_image(
                record["blob"],
                record.get("ext", ".bin"),
                label,
                record["order"],
                images_dir,
                dedupe,
                warnings,
            )
            block["path"] = rel
            block["width"] = width
            block["height"] = height
            block["size"] = size
            block["sha256"] = sha256_bytes(record["blob"])
            block["label"] = label

        if len(image_blocks) > max_images:
            warnings.append(
                f"图片数量 {len(image_blocks)} 超过 max_images={max_images}，"
                "已全部保存，但建议按 image_ids 取用。"
            )

        text_md, truncated_full = _render_markdown(
            blocks, False, max_chars, comments=comments
        )
        text_only_md, truncated_text = _render_markdown(
            blocks, True, max_chars, comments=comments
        )
        header = f"<!-- source: {source} -->\n"
        full_md = header + text_md
        plain_md = header + text_only_md

        document_json = {
            "protocol": 1,
            "source": {
                "path": str(source),
                "format": source.suffix.lower().lstrip("."),
                "sha256": source_hash,
                "size": source.stat().st_size,
                "mtime": source.stat().st_mtime,
                "converted_from": converted_from,
            },
            "blocks": blocks,
            "images": image_blocks,
            "comments": comments,
            "warnings": warnings,
        }
        meta = {
            "engine": f"{ENGINE_NAME} {ENGINE_VERSION}",
            "created_at": now_iso(),
            "source_path": str(source),
            "source_sha256": source_hash,
            "format": source.suffix.lower().lstrip("."),
            "converted_from": converted_from,
            "counts": {
                "blocks": len(blocks),
                "images": len(image_blocks),
                "tables": sum(1 for b in blocks if b.get("type") == "table"),
                "comments": len(comments),
            },
            "warnings": warnings,
        }

        write_json(output_tmp / "document.json", document_json)
        write_json(output_tmp / "meta.json", meta)
        (output_tmp / "document.md").write_text(full_md, encoding="utf-8", newline="\n")
        (output_tmp / "document.text.md").write_text(
            plain_md, encoding="utf-8", newline="\n"
        )

        # Remember previously generated images so stale files can be removed
        # after publishing.  Only touch paths under images/ that the engine
        # itself produced; unrelated files in an existing output folder stay.
        old_images: set[str] = set()
        old_json = output_dir / "document.json"
        if old_json.is_file():
            try:
                old_data = json.loads(old_json.read_text(encoding="utf-8"))
                for item in old_data.get("images", []):
                    rel = item.get("path")
                    if isinstance(rel, str) and rel.startswith("images/"):
                        old_images.add(rel)
            except Exception:
                pass

        publish_dir(output_tmp, output_dir)
        output_tmp = Path()  # ownership transferred; do not clean up

        new_images = {
            b.get("path")
            for b in image_blocks
            if isinstance(b.get("path"), str) and b.get("path")
        }
        for rel in old_images - new_images:
            stale = output_dir / rel
            try:
                if stale.is_file():
                    stale.unlink()
            except OSError:
                pass
    finally:
        shutil.rmtree(work_tmp, ignore_errors=True)
        if str(output_tmp) not in ("", "."):
            shutil.rmtree(output_tmp, ignore_errors=True)

    return ok(
        action="read",
        format=source.suffix.lower().lstrip("."),
        output_dir=str(output_dir),
        document_md=str(output_dir / "document.md"),
        document_text_md=str(output_dir / "document.text.md"),
        document_json=str(output_dir / "document.json"),
        meta_json=str(output_dir / "meta.json"),
        document_hash=source_hash,
        mode=mode,
        blocks=blocks,
        images=image_blocks,
        comments=comments,
        warnings=warnings,
        truncated=bool(truncated_full or truncated_text),
        text=full_md,
    )
