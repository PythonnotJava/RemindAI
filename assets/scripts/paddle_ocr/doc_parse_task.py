"""
PaddleOCR 官方 API - 文档解析 (PaddleOCR-VL-1.6 / PP-StructureV3)
基于官方 demo 改写，仅依赖 requests。

用法:
  python doc_parse_task.py --file <path> --token <token> [--model PaddleOCR-VL-1.6] [--opts <json>]

输出: 解析得到的 Markdown 文本打印到 stdout
进度: 打印到 stderr
"""
import json
import os
import sys
import time
import argparse
import requests

sys.stdout.reconfigure(encoding="utf-8")
sys.stderr.reconfigure(encoding="utf-8")

JOB_URL = "https://paddleocr.aistudio-app.com/api/v2/ocr/jobs"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", required=True)
    parser.add_argument("--model", default="PaddleOCR-VL-1.6")
    parser.add_argument("--token", required=True)
    parser.add_argument("--opts", default="{}")
    args = parser.parse_args()

    headers = {"Authorization": f"bearer {args.token}"}
    optional_payload = json.loads(args.opts)

    file_path = args.file

    # ─── 提交任务 ───
    if file_path.startswith("http"):
        headers["Content-Type"] = "application/json"
        payload = {
            "fileUrl": file_path,
            "model": args.model,
            "optionalPayload": optional_payload,
        }
        resp = requests.post(JOB_URL, json=payload, headers=headers)
    else:
        if not os.path.exists(file_path):
            print(f"文件不存在: {file_path}", file=sys.stderr)
            sys.exit(1)
        data = {
            "model": args.model,
            "optionalPayload": json.dumps(optional_payload),
        }
        with open(file_path, "rb") as f:
            files = {"file": f}
            resp = requests.post(JOB_URL, headers=headers, data=data, files=files)

    if resp.status_code != 200:
        print(f"提交失败 ({resp.status_code}): {resp.text}", file=sys.stderr)
        sys.exit(1)

    job_id = resp.json()["data"]["jobId"]
    print(f"任务已提交: {job_id}", file=sys.stderr)

    # ─── 轮询结果 ───
    for _ in range(120):
        time.sleep(5)
        r = requests.get(f"{JOB_URL}/{job_id}", headers=headers)
        if r.status_code != 200:
            print(f"查询失败: {r.status_code}", file=sys.stderr)
            sys.exit(1)

        state = r.json()["data"]["state"]
        if state == "pending":
            print("排队中...", file=sys.stderr)
        elif state == "running":
            progress = r.json()["data"].get("extractProgress", {})
            total = progress.get("totalPages", "?")
            done = progress.get("extractedPages", "?")
            print(f"处理中: {done}/{total} 页", file=sys.stderr)
        elif state == "done":
            print("解析完成", file=sys.stderr)
            jsonl_url = r.json()["data"]["resultUrl"]["jsonUrl"]
            break
        elif state == "failed":
            error_msg = r.json()["data"].get("errorMsg", "未知错误")
            print(f"任务失败: {error_msg}", file=sys.stderr)
            sys.exit(1)
    else:
        print("超时：任务未在 10 分钟内完成", file=sys.stderr)
        sys.exit(1)

    # ─── 解析结果 ───
    jsonl_resp = requests.get(jsonl_url)
    jsonl_resp.raise_for_status()

    lines = jsonl_resp.text.strip().split("\n")
    all_markdown = []

    for line in lines:
        line = line.strip()
        if not line:
            continue
        data = json.loads(line)
        result = data.get("result", {})
        layout_results = result.get("layoutParsingResults", [])
        for page_result in layout_results:
            md = page_result.get("markdown", {})
            text = md.get("text", "")
            if text:
                all_markdown.append(text)

    if all_markdown:
        print("\n\n---\n\n".join(all_markdown))
    else:
        # fallback: 输出原始 JSON 供调试
        print(jsonl_resp.text)


if __name__ == "__main__":
    main()
