"""
PaddleOCR 官方 API - 连接测试
仅依赖 requests，验证 Token 是否有效。

用法:
  python test_connection.py --token <token>

输出:
  OK           - Token 有效
  ERR:<detail> - 错误
"""
import sys
import argparse
import requests

sys.stdout.reconfigure(encoding="utf-8")
sys.stderr.reconfigure(encoding="utf-8")

JOB_URL = "https://paddleocr.aistudio-app.com/api/v2/ocr/jobs"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--token", required=True)
    args = parser.parse_args()

    try:
        # 用一个无效的 fileUrl 提交，验证 auth 是否通过
        # 如果 token 无效会返回 401/403，如果有效会返回 4xx（参数错误）但说明 token OK
        headers = {
            "Authorization": f"bearer {args.token}",
            "Content-Type": "application/json",
        }
        payload = {
            "fileUrl": "https://example.com/test.png",
            "model": "PP-OCRv6",
        }
        resp = requests.post(JOB_URL, json=payload, headers=headers, timeout=15)

        if resp.status_code == 200:
            # 居然成功了（不太可能但也算通过）
            print("OK")
        elif resp.status_code == 401:
            print("ERR:Token 无效或已过期")
        elif resp.status_code == 403:
            print("ERR:Token 权限不足")
        elif resp.status_code in (400, 422):
            # 参数错误但 auth 通过了
            print("OK")
        else:
            # 其他状态码，但能连上服务器就算 OK
            data = resp.json() if resp.headers.get("content-type", "").startswith("application/json") else {}
            if "data" in data:
                print("OK")
            else:
                print(f"ERR:HTTP {resp.status_code}")
    except requests.exceptions.ConnectionError:
        print("ERR:无法连接到 PaddleOCR 服务器")
    except requests.exceptions.Timeout:
        print("ERR:连接超时")
    except Exception as e:
        print(f"ERR:{e}")


if __name__ == "__main__":
    main()
