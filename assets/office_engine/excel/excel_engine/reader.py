"""Read-only XLSX/XLS workbook extraction for LLM consumption."""

from __future__ import annotations

import csv
import math
import os
import re
import shutil
import tempfile
import uuid
from datetime import date, datetime, time, timedelta
from pathlib import Path
from typing import Any

import xlrd
from openpyxl import load_workbook
from openpyxl.utils import get_column_letter
from PIL import Image

from .protocol import EngineError, ok
from .utils import (
    ensure_dir,
    now_iso,
    publish_dir,
    resolve_path,
    sanitize_filename,
    sha256_file,
    timestamp_slug,
    unique_path,
    write_json,
)

_RANGE_RE = re.compile(r"^\s*([A-Za-z]+)(\d+)\s*:\s*([A-Za-z]+)(\d+)\s*$")


def _int_option(options: dict[str, Any], key: str, default: int) -> int:
    try:
        value = int(options.get(key, default))
    except (TypeError, ValueError):
        return default
    return value


def _bool_option(options: dict[str, Any], key: str, default: bool) -> bool:
    value = options.get(key, default)
    return value is not False and value != 0 and value != "false"


def _col_num(letters: str) -> int:
    n = 0
    for ch in letters.upper():
        n = n * 26 + (ord(ch) - ord("A") + 1)
    return n


def _col_letter(num: int) -> str:
    return get_column_letter(num)


def _parse_range(value: str | None) -> tuple[int, int, int, int] | None:
    if not value:
        return None
    m = _RANGE_RE.match(value)
    if not m:
        raise EngineError(
            "INVALID_ARGS",
            f"range 格式错误: {value!r}",
            hint="使用 A1:F100 这种格式。",
        )
    c1, r1, c2, r2 = m.groups()
    min_col, max_col = sorted((_col_num(c1), _col_num(c2)))
    min_row, max_row = sorted((int(r1), int(r2)))
    return min_row, min_col, max_row, max_col


def _json_value(value: Any) -> Any:
    if value is None:
        return None
    if isinstance(value, (datetime, date, time)):
        return value.isoformat()
    if isinstance(value, timedelta):
        return str(value)
    if isinstance(value, bool):
        return value
    if isinstance(value, float) and (math.isnan(value) or math.isinf(value)):
        return str(value)
    if isinstance(value, (int, float)):
        return value
    if isinstance(value, str):
        return value
    return str(value)


def _text_value(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "TRUE" if value else "FALSE"
    if isinstance(value, datetime):
        # Header dates are often midnight; show 2023-01-01 instead of
        # 2023-01-01T00:00:00 in the Markdown column table.
        if value.time() == time(0, 0):
            return value.date().isoformat()
        return value.isoformat()
    if isinstance(value, (date, time)):
        return value.isoformat()
    return str(value)


def _md_cell(value: Any, max_len: int = 200) -> str:
    text = _text_value(value).replace("|", "\\|").replace("\n", "<br>")
    if len(text) > max_len:
        text = text[:max_len] + "…"
    return text


def _infer_type(values: list[Any]) -> str:
    kinds: set[str] = set()
    for value in values:
        if value is None:
            continue
        if isinstance(value, bool):
            kinds.add("boolean")
        elif isinstance(value, (datetime, date, time)):
            kinds.add("date")
        elif isinstance(value, (int, float)):
            kinds.add("number")
        elif isinstance(value, str):
            kinds.add("string")
        else:
            kinds.add(type(value).__name__)
    if not kinds:
        return "empty"
    if len(kinds) == 1:
        return next(iter(kinds))
    return "mixed"


def _write_csv(
    path: Path,
    rows: list[list[Any]],
) -> None:
    ensure_dir(path.parent)
    with open(path, "w", encoding="utf-8", newline="") as fh:
        writer = csv.writer(fh, lineterminator="\n")
        for row in rows:
            writer.writerow([_text_value(v) for v in row])


def _defined_names_xlsx(wb) -> list[dict[str, str]]:
    result: list[dict[str, str]] = []
    try:
        for name, definition in wb.defined_names.items():
            result.append(
                {
                    "name": str(name),
                    "value": str(getattr(definition, "value", "")),
                }
            )
    except Exception:
        pass
    return result


def _hidden_xlsx(ws) -> tuple[list[int], list[str]]:
    hidden_rows: list[int] = []
    hidden_cols: list[str] = []
    try:
        for idx, dim in ws.row_dimensions.items():
            if getattr(dim, "hidden", False):
                hidden_rows.append(int(idx))
    except Exception:
        pass
    try:
        for letter, dim in ws.column_dimensions.items():
            if getattr(dim, "hidden", False):
                hidden_cols.append(str(letter))
    except Exception:
        pass
    return sorted(hidden_rows), hidden_cols


def _export_images_xlsx(
    ws,
    sheet_slug: str,
    images_dir: Path,
    warnings: list[str],
) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    images = getattr(ws, "_images", []) or []
    for idx, image in enumerate(images, 1):
        try:
            data = image._data()
            if not data:
                continue
            ext = (getattr(image, "format", None) or "png").lower()
            if ext not in ("png", "jpg", "jpeg", "gif", "bmp", "webp", "tiff"):
                ext = "png"
            filename = f"{sheet_slug}-img{idx:02d}.{ext}"
            target = images_dir / filename
            target.write_bytes(data)
            anchor = getattr(image, "anchor", None)
            row = col = None
            try:
                if anchor is not None and getattr(anchor, "_from", None) is not None:
                    row = int(anchor._from.row) + 1
                    col = int(anchor._from.col) + 1
            except Exception:
                pass
            result.append(
                {
                    "path": f"images/{filename}",
                    "sheet": ws.title,
                    "row": row,
                    "col": col,
                    "bytes": len(data),
                }
            )
        except Exception as exc:
            warnings.append(f"sheet {ws.title!r} 第 {idx} 张图片导出失败: {exc}")
    return result


def _read_xlsx(
    path: Path,
    options: dict[str, Any],
    sheet_filter: str | None,
    range_spec: str | None,
    output_tmp: Path,
    warnings: list[str],
) -> tuple[list[dict[str, Any]], list[dict[str, str]]]:
    include_formulas = _bool_option(options, "include_formulas", True)
    include_hidden = _bool_option(options, "include_hidden", True)
    include_images = _bool_option(options, "include_images", True)
    max_rows = max(1, _int_option(options, "max_rows", 200))
    max_cols = max(1, _int_option(options, "max_cols", 50))
    max_cells = max(1, _int_option(options, "max_cells", 20000))
    max_scan_cells = max(1, _int_option(options, "max_scan_cells", 1_000_000))
    max_csv_rows = max(1, _int_option(options, "max_csv_rows", 200000))
    max_formulas = max(1, _int_option(options, "max_formulas", 1000))
    header_row = _int_option(options, "header_row", 1)
    range_bounds = _parse_range(range_spec)

    try:
        wb_values = load_workbook(str(path), data_only=True, read_only=False)
    except Exception as exc:
        raise EngineError(
            "PARSE_FAILED",
            f"无法解析 xlsx: {exc}",
            hint="确认文件未损坏、未加密；.xls 请用 xls 分支。",
        ) from exc
    wb_formulas = None
    if include_formulas:
        try:
            wb_formulas = load_workbook(str(path), data_only=False, read_only=False)
        except Exception as exc:
            warnings.append(f"公式工作簿加载失败，仅输出缓存值: {exc}")

    sheet_names = list(wb_values.sheetnames)
    defined_names = _defined_names_xlsx(wb_values)

    images_dir = output_tmp / "images"
    ensure_dir(images_dir)
    sheets: list[dict[str, Any]] = []
    csv_dir = output_tmp / "sheets"
    ensure_dir(csv_dir)

    try:
        for sheet_index, ws in enumerate(wb_values.worksheets, 1):
            if sheet_filter and ws.title != sheet_filter:
                continue
            if ws.sheet_state != "visible" and not include_hidden:
                continue
            ws_formula = None
            if wb_formulas is not None:
                try:
                    ws_formula = wb_formulas[ws.title]
                except Exception:
                    ws_formula = None

            sheet_warnings: list[str] = []
            max_row = max(0, int(ws.max_row or 0))
            max_col = max(0, int(ws.max_column or 0))
            if max_row == 0 or max_col == 0:
                sheets.append(
                    {
                        "name": ws.title,
                        "state": ws.sheet_state,
                        "dimensions": ws.dimensions,
                        "rows": 0,
                        "columns": 0,
                        "header": [],
                        "preview": [],
                        "columns_meta": [],
                        "formulas": {},
                        "merged": [],
                        "tables": [],
                        "hidden_rows": [],
                        "hidden_cols": [],
                        "images": [],
                        "csv": "",
                        "truncated": False,
                        "warnings": ["空 sheet"],
                    }
                )
                continue

            if range_bounds:
                min_row, min_col, max_row2, max_col2 = range_bounds
                min_row = max(1, min_row)
                min_col = max(1, min_col)
                max_row = min(max_row, max_row2)
                max_col = min(max_col, max_col2)
            else:
                min_row, min_col = 1, 1

            total_rows = max(0, max_row - min_row + 1)
            total_cols = max(0, max_col - min_col + 1)
            total_cells = total_rows * total_cols
            scan_all = total_cells <= max_scan_cells
            if not scan_all:
                sheet_warnings.append(
                    f"sheet 共 {total_cells} 个单元格，超过 max_scan_cells={max_scan_cells}；"
                    "只扫描预览区域，统计可能不完整。"
                )

            if header_row >= min_row and header_row <= max_row:
                data_start = header_row + 1
            else:
                data_start = min_row

            preview_rows = min(max_rows, max(0, max_row - data_start + 1))
            preview_cols = min(max_cols, total_cols)
            if preview_rows * preview_cols > max_cells:
                preview_rows = max(1, max_cells // max(1, preview_cols))
                sheet_warnings.append(
                    f"预览超过 max_cells={max_cells}，已减少到 {preview_rows} 行。"
                )
            preview_cols = max(1, preview_cols)

            header_values: list[Any] = []
            for c in range(min_col, min_col + preview_cols):
                value = None
                if header_row >= min_row and header_row <= max_row:
                    value = ws.cell(header_row, c).value
                header_values.append(
                    value if value not in (None, "") else _col_letter(c)
                )

            # Preview values (formulas fall back to formula text when the
            # cached value is missing).
            preview: list[list[Any]] = []
            for r in range(data_start, data_start + preview_rows):
                row_values: list[Any] = []
                for c in range(min_col, min_col + preview_cols):
                    vcell = ws.cell(r, c)
                    value = vcell.value
                    formula = None
                    if ws_formula is not None:
                        fcell = ws_formula.cell(r, c)
                        if isinstance(fcell.value, str) and fcell.value.startswith("="):
                            formula = fcell.value
                    if value is None and formula is not None:
                        value = formula
                    row_values.append(_json_value(value))
                preview.append(row_values)

            # One scan for counts/formulas.  Do not increment counters while
            # building the preview, otherwise preview rows are counted twice.
            scan_end_row = max_row if scan_all else min(
                max_row, data_start + preview_rows - 1
            )
            scan_end_col = max_col if scan_all else min(
                max_col, min_col + preview_cols - 1
            )
            nonempty_total = 0
            col_nonempty = {c: 0 for c in range(min_col, min_col + preview_cols)}
            col_samples: dict[int, list[Any]] = {c: [] for c in range(min_col, min_col + preview_cols)}
            formulas: dict[str, dict[str, Any]] = {}
            formula_count = 0
            formula_missing_value = 0

            for r in range(data_start, scan_end_row + 1):
                for c in range(min_col, scan_end_col + 1):
                    vcell = ws.cell(r, c)
                    value = vcell.value
                    formula = None
                    if ws_formula is not None:
                        fcell = ws_formula.cell(r, c)
                        if isinstance(fcell.value, str) and fcell.value.startswith("="):
                            formula = fcell.value
                    if value is None and formula is not None:
                        value = formula
                    if value not in (None, ""):
                        nonempty_total += 1
                        if c in col_nonempty:
                            col_nonempty[c] += 1
                            if len(col_samples[c]) < 30:
                                col_samples[c].append(value)
                    if formula is not None:
                        formula_count += 1
                        if vcell.value is None:
                            formula_missing_value += 1
                        if len(formulas) < max_formulas:
                            formulas[vcell.coordinate] = {
                                "formula": formula,
                                "value": _json_value(vcell.value),
                            }

            columns_meta: list[dict[str, Any]] = []
            for offset, c in enumerate(range(min_col, min_col + preview_cols)):
                columns_meta.append(
                    {
                        "index": c,
                        "letter": _col_letter(c),
                        "header": _text_value(header_values[offset]),
                        "type": _infer_type(col_samples[c]),
                        "nonempty": col_nonempty[c],
                    }
                )

            merged = []
            try:
                merged = [str(rng) for rng in ws.merged_cells.ranges]
            except Exception:
                pass
            tables = []
            try:
                for name, table in ws.tables.items():
                    tables.append(
                        {
                            "name": name,
                            "range": getattr(table, "ref", ""),
                        }
                    )
            except Exception:
                pass
            hidden_rows, hidden_cols = _hidden_xlsx(ws)
            images = (
                _export_images_xlsx(ws, sanitize_filename(ws.title, f"sheet{sheet_index}"), images_dir, sheet_warnings)
                if include_images
                else []
            )
            if formula_missing_value:
                sheet_warnings.append(
                    f"{formula_missing_value} 个公式没有缓存值（工作簿可能未在 Excel 中计算过）；"
                    "预览显示公式文本，数值可能为空。"
                )
            chart_count = len(getattr(ws, "_charts", []) or [])
            if chart_count:
                sheet_warnings.append(
                    f"检测到 {chart_count} 个图表；当前只统计数量，不渲染为图片。"
                )

            # Full CSV (values; formulas fall back to cached value).
            csv_name = f"{sheet_index:02d}-{sanitize_filename(ws.title, 'sheet')}.csv"
            csv_path = csv_dir / csv_name
            csv_rows: list[list[Any]] = []
            csv_truncated = False
            written = 0
            for r in range(data_start, max_row + 1):
                if written >= max_csv_rows:
                    csv_truncated = True
                    break
                row: list[Any] = []
                for c in range(min_col, max_col + 1):
                    vcell = ws.cell(r, c)
                    value = vcell.value
                    if value is None and ws_formula is not None:
                        fcell = ws_formula.cell(r, c)
                        if isinstance(fcell.value, str) and fcell.value.startswith("="):
                            value = fcell.value
                    row.append(_text_value(value))
                csv_rows.append(row)
                written += 1
            _write_csv(csv_path, csv_rows)
            if csv_truncated:
                sheet_warnings.append(
                    f"CSV 已截断到 {max_csv_rows} 行；完整数据请用 Excel 打开。"
                )

            truncated = (
                preview_rows < max(0, max_row - data_start + 1)
                or preview_cols < total_cols
                or not scan_all
                or formula_count > len(formulas)
                or csv_truncated
            )
            sheets.append(
                {
                    "name": ws.title,
                    "state": ws.sheet_state,
                    "dimensions": ws.dimensions,
                    "rows": total_rows,
                    "columns": total_cols,
                    "header": [_text_value(v) for v in header_values],
                    "preview": preview,
                    "columns_meta": columns_meta,
                    "formulas": formulas,
                    "formula_count": formula_count,
                    "merged": merged,
                    "tables": tables,
                    "hidden_rows": hidden_rows,
                    "hidden_cols": hidden_cols,
                    "images": images,
                    "charts": chart_count,
                    "csv": f"sheets/{csv_name}",
                    "truncated": truncated,
                    "warnings": sheet_warnings,
                }
            )
    finally:
        try:
            wb_values.close()
        except Exception:
            pass
        if wb_formulas is not None:
            try:
                wb_formulas.close()
            except Exception:
                pass

    if sheet_filter and not sheets:
        raise EngineError(
            "SHEET_NOT_FOUND",
            f"找不到 sheet: {sheet_filter}",
            hint=f"可用 sheet: {sheet_names}",
        )
    return sheets, defined_names


def _xls_date(value: float, datemode: int) -> datetime | None:
    try:
        return xlrd.xldate_as_datetime(value, datemode)
    except Exception:
        return None


def _xls_cell_value(sheet, row: int, col: int, datemode: int) -> Any:
    cell = sheet.cell(row, col)
    if cell.ctype == xlrd.XL_CELL_DATE:
        return _xls_date(cell.value, datemode)
    if cell.ctype == xlrd.XL_CELL_BOOLEAN:
        return bool(cell.value)
    if cell.ctype == xlrd.XL_CELL_ERROR:
        return xlrd.error_text_from_code.get(cell.value, "#ERR")
    if cell.ctype in (xlrd.XL_CELL_EMPTY, xlrd.XL_CELL_BLANK):
        return None
    return cell.value


def _read_xls(
    path: Path,
    options: dict[str, Any],
    sheet_filter: str | None,
    range_spec: str | None,
    output_tmp: Path,
    warnings: list[str],
) -> tuple[list[dict[str, Any]], list[dict[str, str]]]:
    include_hidden = _bool_option(options, "include_hidden", True)
    max_rows = max(1, _int_option(options, "max_rows", 200))
    max_cols = max(1, _int_option(options, "max_cols", 50))
    max_cells = max(1, _int_option(options, "max_cells", 20000))
    max_csv_rows = max(1, _int_option(options, "max_csv_rows", 200000))
    header_row = _int_option(options, "header_row", 1)
    range_bounds = _parse_range(range_spec)

    try:
        book = xlrd.open_workbook(
            str(path), on_demand=True, formatting_info=True
        )
    except Exception:
        try:
            book = xlrd.open_workbook(str(path), on_demand=True)
        except Exception as exc:
            raise EngineError(
                "PARSE_FAILED",
                f"无法解析 xls: {exc}",
                hint="确认文件未损坏、未加密；xlsx 请用 xlsx 分支。",
            ) from exc

    if _bool_option(options, "include_formulas", True):
        warnings.append("xls 格式：xlrd 只能读取缓存值，公式文本不可用。")

    csv_dir = output_tmp / "sheets"
    ensure_dir(csv_dir)
    sheets: list[dict[str, Any]] = []
    state_map = {0: "visible", 1: "hidden", 2: "veryHidden"}
    sheet_names = list(book.sheet_names())

    try:
        for sheet_index, sheet in enumerate(book.sheets(), 1):
            if sheet_filter and sheet.name != sheet_filter:
                continue
            state = state_map.get(getattr(sheet, "visibility", 0), "visible")
            if state != "visible" and not include_hidden:
                continue
            sheet_warnings: list[str] = []
            total_rows = int(sheet.nrows)
            total_cols = int(sheet.ncols)
            if total_rows == 0 or total_cols == 0:
                sheets.append(
                    {
                        "name": sheet.name,
                        "state": state,
                        "dimensions": "",
                        "rows": 0,
                        "columns": 0,
                        "header": [],
                        "preview": [],
                        "columns_meta": [],
                        "formulas": {},
                        "formula_count": 0,
                        "merged": [],
                        "tables": [],
                        "hidden_rows": [],
                        "hidden_cols": [],
                        "images": [],
                        "charts": 0,
                        "csv": "",
                        "truncated": False,
                        "warnings": ["空 sheet"],
                    }
                )
                continue

            if range_bounds:
                min_row, min_col, max_row, max_col = range_bounds
                min_row = max(0, min_row - 1)
                min_col = max(0, min_col - 1)
                max_row = min(total_rows - 1, max_row - 1)
                max_col = min(total_cols - 1, max_col - 1)
            else:
                min_row, min_col = 0, 0
                max_row, max_col = total_rows - 1, total_cols - 1

            total_rows = max(0, max_row - min_row + 1)
            total_cols = max(0, max_col - min_col + 1)
            header_row0 = header_row - 1
            if min_row <= header_row0 <= max_row:
                data_start = header_row0 + 1
            else:
                data_start = min_row

            preview_rows = min(max_rows, max(0, max_row - data_start + 1))
            preview_cols = min(max_cols, total_cols)
            if preview_rows * preview_cols > max_cells:
                preview_rows = max(1, max_cells // max(1, preview_cols))
                sheet_warnings.append(
                    f"预览超过 max_cells={max_cells}，已减少到 {preview_rows} 行。"
                )
            preview_cols = max(1, preview_cols)

            header_values: list[Any] = []
            for c in range(min_col, min_col + preview_cols):
                value = None
                if min_row <= header_row0 <= max_row:
                    value = _xls_cell_value(sheet, header_row0, c, book.datemode)
                header_values.append(
                    value if value not in (None, "") else _col_letter(c + 1)
                )

            col_nonempty = {c: 0 for c in range(min_col, min_col + preview_cols)}
            col_samples: dict[int, list[Any]] = {c: [] for c in range(min_col, min_col + preview_cols)}
            preview: list[list[Any]] = []
            nonempty_total = 0
            for r in range(min_row, max_row + 1):
                for c in range(min_col, max_col + 1):
                    value = _xls_cell_value(sheet, r, c, book.datemode)
                    if value not in (None, ""):
                        nonempty_total += 1
                        if c in col_nonempty:
                            col_nonempty[c] += 1
                            if len(col_samples[c]) < 30:
                                col_samples[c].append(value)

            for r in range(data_start, data_start + preview_rows):
                row_values: list[Any] = []
                for c in range(min_col, min_col + preview_cols):
                    row_values.append(
                        _json_value(_xls_cell_value(sheet, r, c, book.datemode))
                    )
                preview.append(row_values)

            columns_meta: list[dict[str, Any]] = []
            for offset, c in enumerate(range(min_col, min_col + preview_cols)):
                columns_meta.append(
                    {
                        "index": c + 1,
                        "letter": _col_letter(c + 1),
                        "header": _text_value(header_values[offset]),
                        "type": _infer_type(col_samples[c]),
                        "nonempty": col_nonempty[c],
                    }
                )

            merged = []
            for rlo, rhi, clo, chi in getattr(sheet, "merged_cells", []) or []:
                if rhi > rlo + 1 or chi > clo + 1:
                    merged.append(
                        f"{_col_letter(clo + 1)}{rlo + 1}:{_col_letter(chi)}{rhi}"
                    )
            hidden_rows: list[int] = []
            hidden_cols: list[str] = []
            try:
                for r, info in getattr(sheet, "rowinfo_map", {}).items():
                    if getattr(info, "hidden", False):
                        hidden_rows.append(r + 1)
                for c, info in getattr(sheet, "colinfo_map", {}).items():
                    if getattr(info, "hidden", False):
                        hidden_cols.append(_col_letter(c + 1))
            except Exception:
                pass

            csv_name = f"{sheet_index:02d}-{sanitize_filename(sheet.name, 'sheet')}.csv"
            csv_path = csv_dir / csv_name
            csv_rows: list[list[Any]] = []
            csv_truncated = False
            written = 0
            for r in range(data_start, max_row + 1):
                if written >= max_csv_rows:
                    csv_truncated = True
                    break
                csv_rows.append(
                    [
                        _text_value(_xls_cell_value(sheet, r, c, book.datemode))
                        for c in range(min_col, max_col + 1)
                    ]
                )
                written += 1
            _write_csv(csv_path, csv_rows)
            if csv_truncated:
                sheet_warnings.append(f"CSV 已截断到 {max_csv_rows} 行。")

            truncated = (
                preview_rows < max(0, max_row - data_start + 1)
                or preview_cols < total_cols
                or csv_truncated
            )
            sheets.append(
                {
                    "name": sheet.name,
                    "state": state,
                    "dimensions": f"{_col_letter(min_col + 1)}{min_row + 1}:{_col_letter(max_col + 1)}{max_row + 1}",
                    "rows": total_rows,
                    "columns": total_cols,
                    "header": [_text_value(v) for v in header_values],
                    "preview": preview,
                    "columns_meta": columns_meta,
                    "formulas": {},
                    "formula_count": 0,
                    "merged": merged,
                    "tables": [],
                    "hidden_rows": hidden_rows,
                    "hidden_cols": hidden_cols,
                    "images": [],
                    "charts": 0,
                    "csv": f"sheets/{csv_name}",
                    "truncated": truncated,
                    "warnings": sheet_warnings,
                }
            )
    finally:
        try:
            book.release_resources()
        except Exception:
            pass

    if sheet_filter and not sheets:
        raise EngineError(
            "SHEET_NOT_FOUND",
            f"找不到 sheet: {sheet_filter}",
            hint=f"可用 sheet: {sheet_names}",
        )
    return sheets, []


def _render_sheet_md(sheet: dict[str, Any]) -> str:
    lines = [f"## Sheet: {sheet.get('name')}"]
    lines.append("")
    lines.append(f"- 状态: {sheet.get('state')}")
    lines.append(f"- 范围: {sheet.get('dimensions') or '-'}")
    lines.append(f"- 行数: {sheet.get('rows')}")
    lines.append(f"- 列数: {sheet.get('columns')}")
    lines.append(f"- 公式: {sheet.get('formula_count', 0)}")
    lines.append(f"- 合并单元格: {len(sheet.get('merged', []))}")
    lines.append(f"- 表格: {len(sheet.get('tables', []))}")
    hidden_rows = sheet.get("hidden_rows") or []
    hidden_cols = sheet.get("hidden_cols") or []
    if hidden_rows:
        lines.append(f"- 隐藏行: {len(hidden_rows)}")
    if hidden_cols:
        lines.append(f"- 隐藏列: {len(hidden_cols)}")
    lines.append("")

    columns = sheet.get("columns_meta") or []
    if columns:
        lines.append("### 列概览")
        lines.append("")
        lines.append("| 列 | 表头 | 类型 | 非空 |")
        lines.append("| --- | --- | --- | --- |")
        for col in columns:
            lines.append(
                f"| {col.get('letter')} | {_md_cell(col.get('header'), 80)} | "
                f"{col.get('type')} | {col.get('nonempty')} |"
            )
        if len(columns) < int(sheet.get("columns") or 0):
            lines.append("")
            lines.append(
                f"> 仅显示前 {len(columns)}/{sheet.get('columns')} 列；完整数据见 CSV。"
            )
        lines.append("")

    header = sheet.get("header") or []
    preview = sheet.get("preview") or []
    if header and preview:
        lines.append("### 数据预览")
        lines.append("")
        letters = [c.get("letter", "") for c in columns]
        lines.append("| " + " | ".join(letters) + " |")
        lines.append("| " + " | ".join("---" for _ in letters) + " |")
        for row in preview:
            lines.append(
                "| " + " | ".join(_md_cell(v) for v in row) + " |"
            )
        if sheet.get("truncated"):
            lines.append("")
            lines.append("> 预览已截断；完整数据见 CSV。")
        lines.append("")

    formulas = sheet.get("formulas") or {}
    if formulas:
        lines.append("### 公式（前 20 个）")
        lines.append("")
        for idx, (coord, info) in enumerate(formulas.items()):
            if idx >= 20:
                break
            lines.append(
                f"- `{coord}`: `{info.get('formula')}` → `{info.get('value')}`"
            )
        if len(formulas) > 20:
            lines.append(f"- … 共 {len(formulas)} 个公式")
        lines.append("")

    merged = sheet.get("merged") or []
    if merged:
        lines.append("### 合并单元格")
        lines.append("")
        lines.append(", ".join(merged[:30]))
        if len(merged) > 30:
            lines.append(f"… 共 {len(merged)} 个")
        lines.append("")

    if sheet.get("csv"):
        lines.append(f"完整数据: `{sheet.get('csv')}`")
    for warning in sheet.get("warnings") or []:
        lines.append(f"- 警告: {warning}")
    return "\n".join(lines)


def _render_workbook_md(
    source: Path,
    sheets: list[dict[str, Any]],
    defined_names: list[dict[str, str]],
    warnings: list[str],
    max_chars: int,
) -> tuple[str, bool]:
    parts = [f"# 工作簿: {source.stem}", f"源文件: `{source}`"]
    if defined_names:
        parts.append(
            "## 定义名称\n\n"
            + "\n".join(f"- `{d['name']}` = `{d['value']}`" for d in defined_names)
        )
    for sheet in sheets:
        parts.append(_render_sheet_md(sheet))
    if warnings:
        parts.append("## 警告\n\n" + "\n".join(f"- {w}" for w in warnings))
    text = "\n\n".join(parts)
    truncated = False
    if max_chars and max_chars > 0 and len(text) > max_chars:
        text = text[:max_chars].rstrip() + "\n\n... [内容过大，已截断]"
        truncated = True
    return text, truncated


def read_excel(request: dict[str, Any]) -> dict[str, Any]:
    path_value = request.get("path") or request.get("source")
    if not isinstance(path_value, str) or not path_value.strip():
        raise EngineError("INVALID_REQUEST", "缺少 path/source 参数。")
    source = resolve_path(path_value, request.get("base_dir"))
    if not source.is_file():
        raise EngineError("FILE_NOT_FOUND", f"文件不存在: {source}")
    suffix = source.suffix.lower()
    if suffix not in (".xlsx", ".xls"):
        raise EngineError(
            "UNSUPPORTED_FORMAT",
            f"不支持的 Excel 格式: {suffix or '无扩展名'}",
            hint="当前支持 .xlsx 和 .xls。",
        )

    options = request.get("options") or {}
    if not isinstance(options, dict):
        options = {}
    sheet_filter = options.get("sheet")
    if sheet_filter is not None and not isinstance(sheet_filter, str):
        sheet_filter = None
    range_spec = options.get("range")
    if range_spec is not None and not isinstance(range_spec, str):
        range_spec = None
    if range_spec and not sheet_filter:
        raise EngineError(
            "INVALID_ARGS",
            "指定 range 时必须同时指定 sheet，避免对所有 sheet 误用同一范围。",
        )

    stem = sanitize_filename(source.stem, "workbook")
    output_value = request.get("output_dir")
    if isinstance(output_value, str) and output_value.strip():
        output_dir = resolve_path(output_value, request.get("base_dir"))
    else:
        output_dir = Path.cwd() / ".toolshell" / "office_engine" / stem

    ensure_dir(output_dir.parent)
    output_tmp = Path(
        tempfile.mkdtemp(prefix=f".{stem}.out-", dir=str(output_dir.parent))
    )
    warnings: list[str] = []
    try:
        if suffix == ".xlsx":
            sheets, defined_names = _read_xlsx(
                source, options, sheet_filter, range_spec, output_tmp, warnings
            )
            fmt = "xlsx"
        else:
            sheets, defined_names = _read_xls(
                source, options, sheet_filter, range_spec, output_tmp, warnings
            )
            fmt = "xls"

        max_chars = _int_option(options, "max_chars", 100000)
        text_md, truncated = _render_workbook_md(
            source, sheets, defined_names, warnings, max_chars
        )
        # Excel has no image markdown in the workbook text; both views are the
        # same for now, but keep the filename contract used by the Word engine.
        plain_md = text_md

        document_json = {
            "protocol": 1,
            "source": {
                "path": str(source),
                "format": fmt,
                "sha256": sha256_file(source),
                "size": source.stat().st_size,
                "mtime": source.stat().st_mtime,
            },
            "workbook": {
                "sheet_count": len(sheets),
                "defined_names": defined_names,
                "sheets": sheets,
            },
            "warnings": warnings,
        }
        meta = {
            "engine": f"office-excel 0.1.0",
            "created_at": now_iso(),
            "source_path": str(source),
            "source_sha256": document_json["source"]["sha256"],
            "format": fmt,
            "counts": {
                "sheets": len(sheets),
                "rows": sum(int(s.get("rows") or 0) for s in sheets),
                "columns": sum(int(s.get("columns") or 0) for s in sheets),
                "formulas": sum(int(s.get("formula_count") or 0) for s in sheets),
                "images": sum(len(s.get("images") or []) for s in sheets),
            },
            "warnings": warnings,
        }

        write_json(output_tmp / "document.json", document_json)
        write_json(output_tmp / "meta.json", meta)
        (output_tmp / "document.md").write_text(text_md, encoding="utf-8", newline="\n")
        (output_tmp / "document.text.md").write_text(
            plain_md, encoding="utf-8", newline="\n"
        )
        publish_dir(output_tmp, output_dir)
        output_tmp = Path()
    finally:
        if str(output_tmp) not in ("", "."):
            shutil.rmtree(output_tmp, ignore_errors=True)

    return ok(
        action="read",
        format=fmt,
        output_dir=str(output_dir),
        document_md=str(output_dir / "document.md"),
        document_text_md=str(output_dir / "document.text.md"),
        document_json=str(output_dir / "document.json"),
        meta_json=str(output_dir / "meta.json"),
        document_hash=document_json["source"]["sha256"],
        sheets=[
            {
                "name": s.get("name"),
                "rows": s.get("rows"),
                "columns": s.get("columns"),
                "state": s.get("state"),
                "formula_count": s.get("formula_count", 0),
                "columns_meta": s.get("columns_meta", []),
                "merged": s.get("merged", []),
                "hidden_rows": s.get("hidden_rows", []),
                "hidden_cols": s.get("hidden_cols", []),
                "images": s.get("images", []),
                "csv": s.get("csv"),
                "truncated": s.get("truncated"),
            }
            for s in sheets
        ],
        warnings=warnings,
        truncated=truncated,
        text=text_md,
    )


def file_operation(request: dict[str, Any]) -> dict[str, Any]:
    path_value = request.get("path")
    if not isinstance(path_value, str) or not path_value.strip():
        raise EngineError("INVALID_REQUEST", "file 缺少 path 参数。")
    path = resolve_path(path_value, request.get("base_dir"))
    operation = str(request.get("operation") or "info").lower()

    if operation == "info":
        if not path.exists():
            raise EngineError("FILE_NOT_FOUND", f"文件不存在: {path}")
        return ok(
            action="file",
            operation="info",
            path=str(path),
            exists=True,
            is_file=path.is_file(),
            is_dir=path.is_dir(),
            size=path.stat().st_size,
            mtime=path.stat().st_mtime,
            sha256=sha256_file(path) if path.is_file() else "",
            format=path.suffix.lower().lstrip("."),
        )

    if operation == "delete":
        if not path.is_file():
            raise EngineError("FILE_NOT_FOUND", f"文件不存在: {path}")
        mode = str(request.get("mode") or "trash").lower()
        if mode == "permanent":
            if request.get("confirm") is not True:
                raise EngineError(
                    "CONFIRMATION_REQUIRED",
                    "永久删除需要 confirm=true。",
                    hint="默认 mode=trash 会重命名保留可恢复副本。",
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
        return ok(action="file", operation=operation, path=str(path), dest=str(dest))

    raise EngineError(
        "UNSUPPORTED_OPERATION",
        f"不支持的文件操作: {operation}",
        hint="支持 info/delete/copy/move。",
    )
