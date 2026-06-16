"""
PaddleOCR 官方 API - OCR 识别 (PP-OCRv5/v6)
基于官方 demo 改写，仅依赖 requests。

用法:
  python ocr_task.py --file <path> --token <token> [--model PP-OCRv6] [--opts <json>]

输出: 识别到的文本打印到 stdout (JSON 格式)
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
    parser.add_argument("--model", default="PP-OCRv6")
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
    for _ in range(120):  # 最多等 10 分钟
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
            print("识别完成", file=sys.stderr)
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

    # 结果可能是 JSONL 或单行 JSON
    content = jsonl_resp.text.strip()
    lines = content.split("\n") if "\n" in content else [content]
    all_text = []

    for line in lines:
        line = line.strip()
        if not line:
            continue
        data = json.loads(line)

        # 支持两种顶层结构：{result: ...} 或 {logId: ..., result: ...}
        result = data.get("result", data)
        ocr_results = result.get("ocrResults", [])

        for page_result in ocr_results:
            pruned = page_result.get("prunedResult", {})

            # prunedResult 是 dict 时，提取 rec_texts 列表
            if isinstance(pruned, dict):
                rec_texts = pruned.get("rec_texts", [])
                if rec_texts:
                    all_text.extend(rec_texts)
                else:
                    # fallback: 尝试其他可能的字段
                    text = pruned.get("text", "")
                    if text:
                        all_text.append(text)
            elif isinstance(pruned, list):
                for item in pruned:
                    if isinstance(item, dict):
                        text = item.get("text", "")
                        if text:
                            all_text.append(text)
                    elif isinstance(item, str):
                        all_text.append(item)
            elif isinstance(pruned, str):
                all_text.append(pruned)

    if all_text:
        print("\n".join(all_text))
    else:
        # fallback: 输出原始内容供调试
        print(content)


if __name__ == "__main__":
    main()
