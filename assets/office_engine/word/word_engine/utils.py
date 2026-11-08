"""Filesystem and text helpers."""

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

_WINDOWS_RESERVED = {
    "CON",
    "PRN",
    "AUX",
    "NUL",
    *(f"COM{i}" for i in range(1, 10)),
    *(f"LPT{i}" for i in range(1, 10)),
}
_INVALID_FILENAME = re.compile(r'[<>:"/\\|?*\x00-\x1f]')


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


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


def sanitize_filename(name: str, fallback: str = "file", max_len: int = 80) -> str:
    """Make a portable Windows/macOS/Linux file name stem."""
    value = unicodedata.normalize("NFC", str(name or "")).strip()
    value = _INVALID_FILENAME.sub("_", value)
    value = re.sub(r"\s+", " ", value).strip(" .")
    if not value:
        value = fallback
    if value.upper() in _WINDOWS_RESERVED:
        value = f"_{value}"
    # Keep room for suffixes such as "-2" and the extension.
    if len(value) > max_len:
        value = value[:max_len].rstrip(" .")
    return value or fallback


def unique_path(path: str | os.PathLike[str]) -> Path:
    """Return a non-existing path by appending -2, -3, ... to the stem."""
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


def atomic_replace_dir(tmp_dir: str | os.PathLike[str], dest_dir: str | os.PathLike[str]) -> None:
    """Replace *dest_dir* with *tmp_dir* as safely as possible.

    The destination is moved aside first so a failed rename does not destroy
    the previous extraction.  This is intentionally not a transaction across
    filesystems; tmp_dir should live next to dest_dir.
    """
    tmp = Path(tmp_dir)
    dest = Path(dest_dir)
    ensure_dir(dest.parent)
    backup: Path | None = None
    if dest.exists():
        backup = dest.with_name(f"{dest.name}.old-{uuid.uuid4().hex[:8]}")
        os.replace(dest, backup)
    try:
        os.replace(tmp, dest)
    except Exception:
        if backup is not None and not dest.exists():
            os.replace(backup, dest)
        raise
    if backup is not None:
        shutil.rmtree(backup, ignore_errors=True)


def _merge_dir(src: Path, dst: Path) -> None:
    """Merge src into dst, overwriting generated files but preserving extras."""
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
    """Publish a generated directory without deleting unrelated user files.

    If dest_dir does not exist, it is replaced atomically.  If it exists, the
    generated files are merged in (document.md, images/, ...), overwriting only
    same-named generated artifacts.  This is important when the caller points
    the engine at an existing folder such as Desktop/1.
    """
    tmp = Path(tmp_dir)
    dest = Path(dest_dir)
    ensure_dir(dest.parent)
    if not dest.exists():
        os.replace(tmp, dest)
        return
    if not dest.is_dir():
        raise OSError(f"输出路径不是目录: {dest}")
    _merge_dir(tmp, dest)


def atomic_write_file(tmp_file: str | os.PathLike[str], dest_file: str | os.PathLike[str]) -> None:
    tmp = Path(tmp_file)
    dest = Path(dest_file)
    ensure_dir(dest.parent)
    if dest.exists():
        os.replace(dest, dest.with_name(f"{dest.name}.old-{uuid.uuid4().hex[:8]}"))
    os.replace(tmp, dest)


def cleanup_old_backups(directory: str | os.PathLike[str]) -> None:
    """Best-effort removal of *.old-* leftovers next to generated files."""
    try:
        for p in Path(directory).glob("*.old-*"):
            if p.is_dir():
                shutil.rmtree(p, ignore_errors=True)
            else:
                p.unlink(missing_ok=True)
    except OSError:
        pass


def text_or_empty(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ""
