"""Command-line entry point for the standalone Word engine."""

from __future__ import annotations

import argparse
import sys
import traceback

from .protocol import (
    ENGINE_NAME,
    ENGINE_VERSION,
    PROTOCOL_VERSION,
    EngineError,
    capabilities,
    dump_response,
    load_request,
)
from .reader import read_word
from .writer import create_word, edit_word, file_operation


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="office_word",
        description=(
            "Standalone Word (.docx/.doc) engine. "
            "Reads a JSON request from stdin (or --input) and writes one JSON response to stdout."
        ),
    )
    parser.add_argument(
        "command",
        nargs="?",
        choices=["read", "create", "edit", "file", "capabilities"],
        help="Operation to perform.",
    )
    parser.add_argument(
        "--input",
        "-i",
        help="Read the JSON request from this file instead of stdin.",
    )
    parser.add_argument(
        "--pretty",
        action="store_true",
        help="Pretty-print the JSON response.",
    )
    parser.add_argument(
        "--version",
        action="store_true",
        help="Print the engine version and exit.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    # Windows pipes default to the console code page in some environments.
    # Force UTF-8 so the host can decode JSON (and Chinese paths/text) safely.
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
        except Exception:
            pass

    parser = _build_parser()
    args = parser.parse_args(argv)

    if args.version:
        print(f"{ENGINE_NAME} {ENGINE_VERSION} (protocol {PROTOCOL_VERSION})")
        return 0

    if not args.command:
        parser.print_help(sys.stderr)
        return 2

    # Libraries sometimes print to stdout; keep stdout clean for the single
    # JSON response.  All incidental output is redirected to stderr.
    real_stdout = sys.stdout
    sys.stdout = sys.stderr
    try:
        if args.command == "capabilities":
            result = capabilities()
        else:
            request = load_request(args.input)
            action = request.get("action")
            if action is not None and str(action).lower() != args.command:
                raise EngineError(
                    "INVALID_REQUEST",
                    f"请求 action={action!r} 与命令 {args.command!r} 不一致。",
                )
            if args.command == "read":
                result = read_word(request)
            elif args.command == "create":
                result = create_word(request)
            elif args.command == "edit":
                result = edit_word(request)
            elif args.command == "file":
                result = file_operation(request)
            else:
                raise EngineError("INVALID_REQUEST", f"未知命令: {args.command}")
    except EngineError as exc:
        result = exc.to_payload()
    except Exception as exc:  # noqa: BLE001 - protocol boundary
        traceback.print_exc(file=sys.stderr)
        result = EngineError(
            "INTERNAL_ERROR",
            f"引擎内部错误: {exc}",
            hint="请把 stderr 的最后一段日志提供给开发者。",
        ).to_payload()
    finally:
        sys.stdout = real_stdout

    dump_response(result, pretty=args.pretty)
    return 0 if result.get("status") == "ok" else 1


if __name__ == "__main__":
    raise SystemExit(main())
