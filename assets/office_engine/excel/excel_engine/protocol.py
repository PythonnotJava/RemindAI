"""JSON protocol for the standalone Excel engine."""

from __future__ import annotations

import json
import sys
from typing import Any

PROTOCOL_VERSION = 1
ENGINE_NAME = "office-excel"
ENGINE_VERSION = "0.1.0"


class EngineError(Exception):
    def __init__(
        self,
        code: str,
        message: str,
        hint: str | None = None,
        details: Any | None = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.hint = hint
        self.details = details

    def to_payload(self) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "protocol": PROTOCOL_VERSION,
            "status": "error",
            "code": self.code,
            "message": self.message,
        }
        if self.hint:
            payload["hint"] = self.hint
        if self.details is not None:
            payload["details"] = self.details
        return payload


def ok(**payload: Any) -> dict[str, Any]:
    result: dict[str, Any] = {
        "protocol": PROTOCOL_VERSION,
        "status": "ok",
        "engine": f"{ENGINE_NAME} {ENGINE_VERSION}",
    }
    result.update(payload)
    return result


def load_request(path: str | None = None) -> dict[str, Any]:
    try:
        if path and path != "-":
            with open(path, "r", encoding="utf-8-sig") as fh:
                raw = fh.read()
        else:
            raw = sys.stdin.read()
    except OSError as exc:
        raise EngineError("INVALID_REQUEST", f"无法读取请求: {exc}") from exc
    if not raw.strip():
        return {}
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise EngineError("INVALID_REQUEST", f"请求不是合法 JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise EngineError("INVALID_REQUEST", "请求 JSON 必须是对象。")
    return value


def dump_response(payload: dict[str, Any], pretty: bool = False) -> None:
    text = json.dumps(
        payload,
        ensure_ascii=False,
        indent=2 if pretty else None,
        separators=None if pretty else (",", ":"),
    )
    sys.stdout.write(text)
    sys.stdout.write("\n")
    sys.stdout.flush()


def capabilities() -> dict[str, Any]:
    return ok(
        action="capabilities",
        formats={"input": ["xlsx", "xls"], "output": ["md", "json", "csv"]},
        actions={
            "read": {
                "description": "读取 xlsx/xls，输出工作簿摘要、Markdown 预览、JSON 和每个 sheet 的 CSV。",
                "options": [
                    "output_dir",
                    "sheet",
                    "range (A1:F100)",
                    "header_row (1-based; 0=no header)",
                    "max_rows",
                    "max_cols",
                    "max_cells",
                    "max_scan_cells",
                    "max_csv_rows",
                    "max_formulas",
                    "include_hidden",
                    "include_formulas",
                    "include_images",
                ],
            },
            "file": {
                "description": "文件级操作：info / delete / copy / move。",
                "options": ["operation", "path", "mode=trash|permanent", "confirm"],
            },
        },
        limitations=[
            ".xls 由 xlrd 读取：只能读缓存值，公式文本/图片/图表不可用。",
            ".xlsx 图表只统计数量，不渲染为图片；图片可选导出。",
            "不执行公式、不执行宏；只读缓存值。",
            "超宽/超大 sheet 默认只输出预览和列概览，完整数据在 sheets/*.csv。",
        ],
    )
