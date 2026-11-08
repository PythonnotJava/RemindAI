"""Shared protocol helpers for the standalone Office Word engine.

The engine is deliberately independent from RemindAI/Flutter.  It speaks a
small JSON protocol over stdin/stdout so it can be driven by any host:

    echo '{"action":"read","path":"report.docx"}' | python office_word.py read

stdout is reserved for one JSON response.  All diagnostics go to stderr.
"""

from __future__ import annotations

import json
import sys
from typing import Any

PROTOCOL_VERSION = 1
ENGINE_NAME = "office-word"
ENGINE_VERSION = "0.1.0"


class EngineError(Exception):
    """An expected, user-actionable engine error."""

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
    """Read a JSON request from *path* (or stdin)."""
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
        raise EngineError(
            "INVALID_REQUEST",
            f"请求不是合法 JSON: {exc}",
            hint="请求必须是一个 JSON 对象。",
        ) from exc

    if not isinstance(value, dict):
        raise EngineError("INVALID_REQUEST", "请求 JSON 必须是对象。")
    return value


def dump_response(payload: dict[str, Any], pretty: bool = False) -> None:
    """Write exactly one JSON response to stdout."""
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
        formats={
            "input": ["docx", "doc"],
            "output": ["docx"],
        },
        actions={
            "read": {
                "description": "读取 docx/doc，输出 Markdown、JSON、图片、批注和稳定 block_id。",
                "options": [
                    "output_dir",
                    "mode=full|text",
                    "include_images",
                    "max_images",
                    "max_chars",
                    "force",
                ],
            },
            "create": {
                "description": "从 Markdown 或 blocks 新建 docx。",
                "options": ["output", "markdown", "blocks", "images", "highlight"],
            },
            "edit": {
                "description": "修改现有 docx，默认输出新文件。",
                "options": [
                    "source",
                    "output",
                    "in_place",
                    "document_hash",
                    "highlight=none|visual",
                    "keep_deleted",
                    "operations (replace_text/insert/delete/center_tables/...)",
                ],
            },
            "file": {
                "description": "文件级操作：info / delete / copy / move。",
                "options": ["operation", "path", "mode=trash|permanent", "confirm"],
            },
        },
        limitations=[
            "MVP 不支持真正的 Word 修订（track changes），仅支持视觉高亮。",
            "批注支持读取，但暂不支持新增/删除/回复批注。",
            "MVP 不支持复杂图表、SmartArt、公式和文本框的完整编辑。",
            "输入 .doc 需要系统安装 LibreOffice（soffice）；输出始终为 .docx。",
            "编辑复杂文档时可能丢失 python-docx 不支持的格式，请务必使用新文件并校验。",
        ],
    )
