"""
火山引擎（豆包）声音复刻 TTS - 流式合成

基于火山引擎 openspeech SSE API (seed-icl-2.0)，支持声音复刻和情感控制。

用法:
  python volcano_tts.py --text "要合成的文本" --appid <appid> --token <access_token> --voice <voice_type> [options]

选项:
  --text         要合成的文本 (必需)
  --appid        火山引擎 App ID (必需)
  --token        Access Token (必需)
  --voice        音色 ID / voice_type (必需)
  --output       输出文件路径 (默认: stdout 输出 base64)
  --format       音频格式 mp3/wav (默认: wav)
  --sample-rate  采样率 (默认: 24000)
  --speed        语速调节 -50~100 (默认: 0)
  --loudness     音量调节 -50~100 (默认: 0)
  --context      情感/语气控制文本 (可选)

输出:
  成功: JSON {"status": "ok", "audio_base64": "...", "format": "wav"}
  失败: JSON {"status": "error", "message": "..."}
"""
import argparse
import base64
import json
import sys
import uuid
from io import BytesIO

try:
    import requests
except ImportError:
    print(json.dumps({"status": "error", "message": "缺少 requests 库，请运行: pip install requests"}))
    sys.exit(1)

sys.stdout.reconfigure(encoding="utf-8")
sys.stderr.reconfigure(encoding="utf-8")

TTS_URL = "https://openspeech.bytedance.com/api/v3/tts/unidirectional/sse"


def mp3_to_wav(mp3_data: bytes) -> bytes:
    """MP3 转 WAV (需要 pydub + ffmpeg)"""
    try:
        from pydub import AudioSegment
        audio = AudioSegment.from_file(BytesIO(mp3_data), format="mp3")
        wav_io = BytesIO()
        audio.export(wav_io, format="wav")
        return wav_io.getvalue()
    except ImportError:
        # 没有 pydub 就直接返回 mp3
        print(json.dumps({"status": "error", "message": "缺少 pydub 库，无法转换为 wav，请安装: pip install pydub"}))
        sys.exit(1)


def synthesize(text: str, appid: str, token: str, voice: str,
               sample_rate: int = 24000, speed: int = 0, loudness: int = 0,
               context: str = "", output_format: str = "wav") -> dict:
    """调用火山引擎 TTS SSE 接口合成语音"""
    headers = {
        "X-Api-App-Id": appid,
        "X-Api-Access-Key": token,
        "X-Api-Resource-Id": "seed-icl-2.0",
        "Content-Type": "application/json",
        "Connection": "keep-alive",
    }

    additions = {
        "explicit_language": "zh-cn",
        "disable_markdown_filter": True,
        "enable_latex_tn": True,
    }
    if context:
        additions["context_texts"] = [context]

    params = {
        "user": {"uid": str(uuid.uuid4())},
        "req_params": {
            "text": text,
            "speaker": voice,
            "audio_params": {
                "format": "mp3",
                "sample_rate": sample_rate,
                "enable_timestamp": True,
                "speech_rate": speed,
                "loudness_rate": loudness,
            },
            "additions": json.dumps(additions, ensure_ascii=False),
        },
    }

    print(f"正在合成: {text[:30]}...", file=sys.stderr)

    try:
        resp = requests.post(TTS_URL, headers=headers, json=params, stream=True, timeout=30)
        if resp.status_code != 200:
            return {"status": "error", "message": f"HTTP {resp.status_code}: {resp.text[:200]}"}

        audio_data = bytearray()
        for line in resp.iter_lines():
            if not line:
                continue
            line_str = line.decode("utf-8").strip()
            if not line_str.startswith("data:"):
                continue
            data_str = line_str[len("data:"):].strip()
            if not data_str:
                continue
            try:
                data = json.loads(data_str)
                if data.get("code") == 0 and "data" in data and data["data"]:
                    chunk = base64.b64decode(data["data"])
                    audio_data.extend(chunk)
                elif data.get("code") == 20000000:
                    break
            except json.JSONDecodeError:
                continue

        if not audio_data:
            return {"status": "error", "message": "流结束但未收到音频数据"}

        # 转换格式
        if output_format == "wav":
            final_audio = mp3_to_wav(bytes(audio_data))
        else:
            final_audio = bytes(audio_data)

        audio_b64 = base64.b64encode(final_audio).decode("utf-8")
        return {"status": "ok", "audio_base64": audio_b64, "format": output_format}

    except requests.exceptions.Timeout:
        return {"status": "error", "message": "请求超时"}
    except requests.exceptions.ConnectionError as e:
        return {"status": "error", "message": f"连接失败: {e}"}
    except Exception as e:
        return {"status": "error", "message": f"合成失败: {e}"}


def main():
    parser = argparse.ArgumentParser(description="火山引擎声音复刻 TTS")
    parser.add_argument("--text", required=True, help="要合成的文本")
    parser.add_argument("--appid", required=True, help="App ID")
    parser.add_argument("--token", required=True, help="Access Token")
    parser.add_argument("--voice", required=True, help="音色 ID")
    parser.add_argument("--output", default="", help="输出文件路径 (不指定则输出 base64 JSON)")
    parser.add_argument("--format", default="wav", choices=["mp3", "wav"], help="音频格式")
    parser.add_argument("--sample-rate", type=int, default=24000, help="采样率")
    parser.add_argument("--speed", type=int, default=0, help="语速 -50~100")
    parser.add_argument("--loudness", type=int, default=0, help="音量 -50~100")
    parser.add_argument("--context", default="", help="情感/语气控制")
    args = parser.parse_args()

    result = synthesize(
        text=args.text,
        appid=args.appid,
        token=args.token,
        voice=args.voice,
        sample_rate=args.sample_rate,
        speed=args.speed,
        loudness=args.loudness,
        context=args.context,
        output_format=args.format,
    )

    if result["status"] == "ok" and args.output:
        audio_bytes = base64.b64decode(result["audio_base64"])
        with open(args.output, "wb") as f:
            f.write(audio_bytes)
        result = {"status": "ok", "file": args.output, "format": args.format}

    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
