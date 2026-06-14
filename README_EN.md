<div align="center">
  <img src="snapshots/logos/logo_egg.png" alt="RemindAI Logo" width="128" />
  <h1>🧠 RemindAI</h1>
  <p><strong>Open-source Desktop AI Assistant — Not just chat, a real Tool Shell</strong></p>
  <p>
    <a href="./README.md">🌐 中文</a> |
    <a href="https://github.com/PythonnotJava/RemindAI/releases">📦 Download</a> |
    <a href="#-getting-started">🚀 Getting Started</a>
  </p>
  <p>
    <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License" />
    <img src="https://img.shields.io/badge/platform-Windows-brightgreen.svg" alt="Platform" />
    <img src="https://img.shields.io/badge/Flutter-3.12+-02569B.svg?logo=flutter" alt="Flutter" />
    <img src="https://img.shields.io/badge/MCP-purple.svg" alt="MCP" />
  </p>
</div>

---

<p align="center">
  <img src="snapshots/results_promotion.png" alt="RemindAI Showcase" width="900" />
</p>

---

## 💡 What is RemindAI

RemindAI is an **open-source desktop AI assistant** built around a complete **ToolShell** layer that gives LLMs the ability to manipulate files, execute code, call external tools, and manage persistent memory — turning AI into a real productivity tool.

> 🎯 In one line: **Free AI from the chatbox — give it an operating system.**

### 🆚 How it differs from typical AI clients

| | 🔵 Typical AI Client | 🟣 RemindAI |
|---|---|---|
| 📁 File Ops | ❌ Not supported | ✅ Built-in sandboxed filesystem |
| 💻 Code Exec | ❌ Not supported | ✅ Built-in Python/Shell executor |
| 🧠 Memory | ❌ None or context-only | ✅ Vector semantic memory + SQLite |
| 🔌 Extensions | ⚠️ Limited | ✅ MCP + Skills + Capability plugins |
| 🤝 Multi-Agent | ⚠️ Side-by-side windows | ✅ Real collaboration with routing |

---

## 📊 Feature Completion

| Module | Status | Notes |
|---|---|---|
| AI Chat Core (LLM + tool calling) | ✅ | AgentLoop streaming + event-driven UI |
| Three LLM Protocols (OpenAI/Anthropic/Gemini) | ✅ | Independent clients, streaming+tools+multimodal |
| ToolShell Meta-Skill | ✅ | read/write/delete/search/exec/python + rg/fd/rtk |
| Schedule Meta-Skill | ✅ | 7 tools CRUD + review + archive |
| System Meta-Skill | ✅ | Env probe + sanitized env vars |
| MCP Multi-Transport | ✅ | stdio / SSE / Streamable HTTP |
| Vector Memory | ✅ | Qdrant + SQLite dual-write + auto failover |
| Pluggable Capability | ✅ | Search landed, framework extensible |
| Skills System | ✅ | ZIP import / sort / activate |
| Model Card Management | ✅ | CRUD + logo + drag-sort |
| Multi-Agent Collaboration | ⚡ | Framework built, execution loop ongoing |
| Domain Experts | ✅ | Preset/custom roles + skill binding |
| Conversation Export | ✅ | MD / PDF / Word / HTML |
| Desktop Experience | ✅ | Tray / notifications / splash / theme animation |

---

## 🌟 More Features

| Feature | Description |
|---|---|
| 🐚 ToolShell | File sandbox + Python/Shell exec + rg/fd/rtk + RTK compression 60-90% token savings |
| 🔌 MCP Protocol | stdio/SSE/Streamable HTTP + auto-discovery + drag-and-drop management |
| 🧠 Vector Memory | Qdrant semantic search + SQLite backup + auto-ops + index rebuild |
| 🤝 Multi-Agent | Commander/Worker/Reviewer roles + permission isolation + auto-routing |
| 🎨 Multi-Model | OpenAI/Anthropic/Gemini native + streaming reasoning chain + multimodal |
| 🧩 Capability | Pluggable architecture, Custom → MCP → ToolShell three-tier routing |
| 📦 Skills | SKILL.md + tools.json format, one-click ZIP import |
| 🔍 Web Search | Tavily / Brave / Baidu AI Search, session-level toggle |
| 📋 Schedule | SCHEDULE.md driven, P0/P1/P2 priority, AI proactive review |
| 👤 Domain Experts | Preset/custom roles + dedicated system prompts |
| 🖼️ Built-in Tools | Gemini image gen / Formula OCR / PaddleOCR / Flowchart / Rich-text |
| 📤 Export | Markdown / PDF / Word / HTML |
| 🌍 i18n | Full Chinese and English |
| 🎨 Themes | Material 3 light/dark + ripple transition animation |

### 📦 Bundled CLI Tools

The app ships with these executables — no extra installation needed:

| Tool | Description | Source |
|---|---|---|
| `rg` | [ripgrep](https://github.com/BurntSushi/ripgrep) — blazing fast regex search | BurntSushi/ripgrep |
| `fd` | [fd](https://github.com/sharkdp/fd) — modern file finder | sharkdp/fd |
| `rtk` | [RTK](https://github.com/nicobailey/rtk) — Token compressor, 60-90% output reduction | nicobailey/rtk |

---

## 🚀 Getting Started

### 📥 Download

Head to [Releases](https://github.com/PythonnotJava/RemindAI/releases) for pre-built packages:

| Platform | Status | Notes |
|---|---|---|
| 🪟 Windows | ✅ Officially supported | Installer available |
| 🐧 Linux | 🔧 Build from source | Compiles and runs fine |
| 🍎 macOS | 🔧 Build from source | Compiles and runs fine |

### 🔨 Build from Source

```bash
# Requirements: Flutter SDK >= 3.12.1
git clone https://github.com/PythonnotJava/RemindAI.git
cd RemindAI

# Windows
flutter build windows --release --tree-shake-icons --split-debug-info=./debug-info

# Linux / macOS
flutter build linux --release --tree-shake-icons --split-debug-info=./debug-info
flutter build macos --release --tree-shake-icons --split-debug-info=./debug-info
```

---

## 🖼️ Screenshots

<details>
<summary>📸 Click to expand</summary>

| Feature | Screenshot |
|---|---|
| 🏠 Main Interface | <img src="snapshots/main_page.png" width="600" /> |
| 📁 Working Directory | <img src="snapshots/work_dir.png" width="600" /> |
| 🔌 MCP Services | <img src="snapshots/mcp_support.png" width="600" /> |
| 🧠 Memory System | <img src="snapshots/memory_use.png" width="600" /> |
| 🤝 Multi-Agent | <img src="snapshots/muti_agents.jpg" width="600" /> |
| 📦 Skills System | <img src="snapshots/skill_support.png" width="600" /> |

</details>

---

## 🙏 Acknowledgments

Thanks to **Yu** for designing the delightful logo that brings life and personality to RemindAI.

---

## ☕ Sponsor

If RemindAI helps you, feel free to support development ~

<p align="center">
  <img src="snapshots/sponsor/wechat.jpg" alt="WeChat" width="200" />
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
  <img src="snapshots/sponsor/alipay.jpg" alt="Alipay" width="200" />
</p>
<p align="center">
  <sub>💚 WeChat &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; 🔵 Alipay</sub>
</p>

---

## 📄 License

[MIT License](./LICENSE) — Copyright (c) 2026 PythonnotJava

<div align="center">
  <sub>Built with Flutter and passion ❤️</sub>
</div>
