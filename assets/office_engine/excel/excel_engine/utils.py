"""Filesystem helpers for the standalone Excel engine."""

from __future__ import annotations

import hashlib
import os
import re
import shutil
import unicodedata
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

_INVALID_FILENAME = re.compile(r'[<>:"/\\|?*\x00-\x1f]')
_RESERVED = {
    "CON",
    "PRN",
    "AUX",
    "NUL",
    *(f"COM{i}" for i in range(1, 10)),
    *(f"LPT{i}" for i in range(1, 10)),
}


def sha256_file(path: str | os.PathLike[str]) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def timestamp_slug() -> str:
    return datetime.now().strftime("%Y%m%d-%H%M%S")


def ensure_dir(path: str | os.PathLike[str]) -> Path:
    p = Path(path)
    p.mkdir(parents=True, exist_ok=True)
    return p


def resolve_path(value: str, base: str | os.PathLike[str] | None = None) -> Path:
    p = Path(value).expanduser()
    if not p.is_absolute():
        p = Path(base or os.getcwd()) / p
    return p.resolve()


def sanitize_filename(name: str, fallback: str = "sheet", max_len: int = 80) -> str:
    value = unicodedata.normalize("NFC", str(name or "")).strip()
    value = _INVALID_FILENAME.sub("_", value)
    value = re.sub(r"\s+", " ", value).strip(" .")
    if not value:
        value = fallback
    if value.upper() in _RESERVED:
        value = f"_{value}"
    if len(value) > max_len:
        value = value[:max_len].rstrip(" .")
    return value or fallback


def unique_path(path: str | os.PathLike[str]) -> Path:
    p = Path(path)
    if not p.exists():
        return p
    for i in range(2, 10000):
        candidate = p.with_name(f"{p.stem}-{i}{p.suffix}")
        if not candidate.exists():
            return candidate
    raise RuntimeError(f"无法为 {p} 找到可用文件名")


def write_json(path: str | os.PathLike[str], value: Any) -> None:
    import json

    p = Path(path)
    ensure_dir(p.parent)
    with open(p, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(value, fh, ensure_ascii=False, indent=2)
        fh.write("\n")


def _merge_dir(src: Path, dst: Path) -> None:
    ensure_dir(dst)
    for item in src.iterdir():
        target = dst / item.name
        if item.is_dir():
            if target.exists() and target.is_dir():
                _merge_dir(item, target)
            elif target.exists():
                raise OSError(f"输出路径冲突（需要目录但已存在文件）: {target}")
            else:
                os.replace(item, target)
        else:
            if target.exists() and target.is_dir():
                raise OSError(f"输出路径冲突（需要文件但已存在目录）: {target}")
            os.replace(item, target)
    shutil.rmtree(src, ignore_errors=True)


def publish_dir(tmp_dir: str | os.PathLike[str], dest_dir: str | os.PathLike[str]) -> None:
    """Publish generated files without deleting unrelated user files."""
    tmp = Path(tmp_dir)
    dest = Path(dest_dir)
    ensure_dir(dest.parent)
    if not dest.exists():
        os.replace(tmp, dest)
        return
    if not dest.is_dir():
        raise OSError(f"输出路径不是目录: {dest}")
    _merge_dir(tmp, dest)
