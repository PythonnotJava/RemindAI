"""
测试三个内置元技能是否会被 LLM 实际调用。

用法：
  python test_meta_skills.py --base-url <url> --api-key <key> --model <model>

测试场景：
  1. ToolShell: "帮我看看当前目录有什么文件" → 期望调用 toolshell_read/toolshell_search
  2. Schedule: "帮我规划一下接下来要做的事" → 期望调用 schedule_load/schedule_add_task
  3. System: "我电脑上装了哪些开发工具" → 期望调用 system_probe

脚本会向模型发送请求（带工具定义），检查响应是否包含 tool_calls。
"""

import argparse
import json
import sys
from urllib.request import Request, urlopen


def load_tools(path: str) -> list:
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)


def call_llm(base_url: str, api_key: str, model: str,
             messages: list, tools: list) -> dict:
    url = f"{base_url.rstrip('/')}/v1/chat/completions"
    body = {
        "model": model,
        "messages": messages,
        "tools": tools,
        "tool_choice": "auto",
    }
    req = Request(url, data=json.dumps(body).encode(),
                  headers={
                      "Content-Type": "application/json",
                      "Authorization": f"Bearer {api_key}",
                  })
    with urlopen(req, timeout=60) as resp:
        return json.loads(resp.read())


def test_scenario(name: str, user_input: str, system_prompt: str,
                  tools: list, expected_tools: list,
                  base_url: str, api_key: str, model: str) -> bool:
    print(f"\n{'='*60}")
    print(f"测试: {name}")
    print(f"输入: {user_input}")
    print(f"期望工具: {expected_tools}")
    print(f"{'='*60}")

    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_input},
    ]

    try:
        resp = call_llm(base_url, api_key, model, messages, tools)
    except Exception as e:
        print(f"  ❌ API 调用失败: {e}")
        return False

    choice = resp.get("choices", [{}])[0]
    message = choice.get("message", {})
    tool_calls = message.get("tool_calls", [])
    content = message.get("content", "")

    if tool_calls:
        called_names = [tc["function"]["name"] for tc in tool_calls]
        print(f"  ✓ 模型调用了工具: {called_names}")
        hit = any(t in called_names for t in expected_tools)
        if hit:
            print(f"  ✅ 命中期望工具!")
        else:
            print(f"  ⚠️ 调用了工具但不在期望列表中")
        for tc in tool_calls:
            print(f"    - {tc['function']['name']}({tc['function'].get('arguments', '')})")
        return hit
    else:
        print(f"  ❌ 模型未调用任何工具")
        if content:
            print(f"  回复: {content[:200]}")
        return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--api-key", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--assets-dir", default=r"C:\Users\25654\Desktop\AgentShell\RemindAI\assets\default_skills")
    args = parser.parse_args()

    # 加载工具定义
    toolshell_tools = load_tools(f"{args.assets_dir}/toolshell/tools.json")
    schedule_tools = load_tools(f"{args.assets_dir}/schedule/tools.json")
    system_tools = load_tools(f"{args.assets_dir}/system/tools.json")
    all_tools = toolshell_tools + schedule_tools + system_tools

    # 加载 SKILL.md 作为 system prompt
    prompts = []
    for skill_dir in ["toolshell", "schedule", "system"]:
        with open(f"{args.assets_dir}/{skill_dir}/SKILL.md", 'r', encoding='utf-8') as f:
            prompts.append(f.read())
    system_prompt = "\n\n---\n\n".join(prompts)

    print(f"已加载 {len(all_tools)} 个工具定义")
    print(f"System prompt: {len(system_prompt)} 字符")
    print(f"模型: {args.model}")

    # 测试场景
    results = []

    # 1. ToolShell - 文件操作
    results.append(test_scenario(
        name="ToolShell - 文件读取",
        user_input="帮我看看当前项目根目录下有哪些文件",
        system_prompt=system_prompt,
        tools=all_tools,
        expected_tools=["toolshell_search", "toolshell_read", "toolshell_exec"],
        base_url=args.base_url, api_key=args.api_key, model=args.model,
    ))

    # 2. Schedule - 计划管理
    results.append(test_scenario(
        name="Schedule - 加载计划",
        user_input="看看当前的工作计划，有哪些待办任务",
        system_prompt=system_prompt,
        tools=all_tools,
        expected_tools=["schedule_load", "schedule_review"],
        base_url=args.base_url, api_key=args.api_key, model=args.model,
    ))

    # 3. Schedule - 添加任务
    results.append(test_scenario(
        name="Schedule - 规划任务",
        user_input="我需要做三件事：1.修复登录bug 2.加上暗黑模式 3.写单元测试。帮我规划一下优先级并加入计划",
        system_prompt=system_prompt,
        tools=all_tools,
        expected_tools=["schedule_load", "schedule_add_task"],
        base_url=args.base_url, api_key=args.api_key, model=args.model,
    ))

    # 4. System - 环境探测
    results.append(test_scenario(
        name="System - 环境探测",
        user_input="我电脑上装了哪些开发工具？帮我探测一下",
        system_prompt=system_prompt,
        tools=all_tools,
        expected_tools=["system_probe"],
        base_url=args.base_url, api_key=args.api_key, model=args.model,
    ))

    # 5. ToolShell - Python 执行
    results.append(test_scenario(
        name="ToolShell - Python 执行",
        user_input="用matplotlib画一个sin函数的图",
        system_prompt=system_prompt,
        tools=all_tools,
        expected_tools=["toolshell_run_python"],
        base_url=args.base_url, api_key=args.api_key, model=args.model,
    ))

    # 汇总
    print(f"\n{'='*60}")
    print("测试结果汇总")
    print(f"{'='*60}")
    passed = sum(1 for r in results if r)
    total = len(results)
    labels = [
        "ToolShell 文件读取",
        "Schedule 加载计划",
        "Schedule 规划任务",
        "System 环境探测",
        "ToolShell Python执行",
    ]
    for label, result in zip(labels, results):
        status = "✅" if result else "❌"
        print(f"  {status} {label}")
    print(f"\n通过: {passed}/{total}")

    if passed < total:
        print("\n未通过的场景说明模型在该 prompt 下不会主动调用对应工具。")
        print("可能原因: prompt 指引不够强、模型倾向直接回答而非调工具。")
    sys.exit(0 if passed == total else 1)


if __name__ == "__main__":
    main()
