"""Optional LibreOffice conversion for legacy .doc input."""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from .protocol import EngineError


def find_soffice() -> str | None:
    """Locate LibreOffice headless executable."""
    for name in ("soffice", "soffice.exe", "libreoffice"):
        found = shutil.which(name)
        if found:
            return found

    candidates = [
        r"C:\Program Files\LibreOffice\program\soffice.exe",
        r"C:\Program Files (x86)\LibreOffice\program\soffice.exe",
        "/Applications/LibreOffice.app/Contents/MacOS/soffice",
        "/usr/bin/soffice",
        "/usr/local/bin/soffice",
        "/opt/libreoffice/program/soffice",
    ]
    for candidate in candidates:
        if Path(candidate).is_file():
            return candidate
    return None


def convert_doc_to_docx(
    doc_path: str | os.PathLike[str],
    out_dir: str | os.PathLike[str],
    timeout: int = 120,
) -> Path:
    """Convert a legacy .doc to .docx using LibreOffice.

    Raises EngineError(MISSING_DEPENDENCY) when LibreOffice is unavailable,
    and EngineError(CONVERSION_FAILED) when conversion produces no file.
    """
    source = Path(doc_path).resolve()
    if not source.is_file():
        raise EngineError("FILE_NOT_FOUND", f"文件不存在: {source}")
    if source.suffix.lower() != ".doc":
        raise EngineError("INVALID_FORMAT", f"不是 .doc 文件: {source}")

    soffice = find_soffice()
    if not soffice:
        raise EngineError(
            "MISSING_DEPENDENCY",
            "读取 .doc 需要 LibreOffice（soffice），但未找到。",
            hint="安装 LibreOffice 后重试，或先把文件另存为 .docx。",
        )

    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    profile = Path(tempfile.mkdtemp(prefix="office_word_lo_"))
    profile_uri = profile.as_uri()
    cmd = [
        soffice,
        "--headless",
        "--norestore",
        "--nolockcheck",
        "--nodefault",
        f"-env:UserInstallation={profile_uri}",
        "--convert-to",
        "docx",
        "--outdir",
        str(out),
        str(source),
    ]
    try:
        proc = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise EngineError(
            "CONVERSION_TIMEOUT",
            f".doc 转换超时（>{timeout}s）。",
        ) from exc
    except OSError as exc:
        raise EngineError("CONVERSION_FAILED", f"无法启动 LibreOffice: {exc}") from exc
    finally:
        shutil.rmtree(profile, ignore_errors=True)

    target = out / f"{source.stem}.docx"
    if not target.is_file():
        stderr = proc.stderr.decode("utf-8", "replace").strip()
        raise EngineError(
            "CONVERSION_FAILED",
            f"LibreOffice 未能生成 docx（退出码 {proc.returncode}）。",
            details=stderr[-2000:] if stderr else None,
            hint="确认文件未加密、未损坏，或先用 Word/WPS 另存为 .docx。",
        )
    return target
