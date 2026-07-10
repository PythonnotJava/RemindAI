<div align="center">
  <img src="snapshots/logos/logo_egg.png" alt="RemindAI Logo" width="128" />
  <h1>🧠 RemindAI</h1>
  <p><strong>Open-source Desktop AI Assistant — Beyond just chat</strong></p>
  <p>
    <a href="./README.md">🌐 中文</a> |
    <a href="https://github.com/PythonnotJava/RemindAI/releases">📦 Download</a> |
    <a href="#-getting-started">🚀 Getting Started</a>
  </p>
  <p>
    <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License" />
    <img src="https://img.shields.io/badge/platform-Windows-brightgreen.svg" alt="Platform" />
    <img src="https://img.shields.io/badge/Flutter-3.44+-02569B.svg?logo=flutter" alt="Flutter" />
       <img src="https://img.shields.io/badge/MCP Support-purple.svg" alt="MCP" />
    <img src="https://img.shields.io/badge/Skill Support-purple.svg" alt="Skill" />
    <img src="https://img.shields.io/badge/API Server-green.svg" alt="API Server" />
    <img src="https://img.shields.io/badge/🐱 Global Pet Agent-orange.svg" alt="Pet Agent" />
   </p>
</div>

---

<p align="center">
  <img src="snapshots/results_promotion.png" alt="RemindAI Showcase" width="900" />
</p>

---

## 💡 What is RemindAI

RemindAI is an **open-source desktop AI assistant** built around a complete **ToolShell** layer that gives LLMs the ability to manipulate files, execute code, call external tools, manage persistent memory, and autonomously plan tasks — turning AI into a productivity tool that can actually *do* things, not just talk about them.

> 🎯 Beyond the chatbox — give AI real agency.

### 🆚 How it differs from typical AI clients

| | 🔵 Typical AI Client | 🟣 RemindAI |
|---|---|---|
| 📁 File Ops | ❌ Not supported | ✅ Built-in sandboxed filesystem |
| 💻 Code Exec | ❌ Not supported | ✅ Built-in Python/Shell/JS executor |
| 🧠 Memory | ❌ None or context-only | ✅ Vector semantic memory + SQLite + soft-failure filter |
| 🔌 Extensions | ⚠️ Limited | ✅ MCP + four-layer Skills + Capability plugins |
| 🤝 Multi-Agent | ⚠️ Side-by-side windows | ✅ Real collaboration with routing & permission isolation + parallel doc comprehension |
| 🔄 AgentLoop | ❌ None | ✅ Controllable cyclic pipeline: Think→Write→Test→Verify |
| 📦 Skill Import | ⚠️ Single import | ✅ One-click ZIP import + batch import |
| 🌐 External API | ❌ Not supported | ✅ Built-in HTTP API server with three endpoint types |
| 🐱 Desktop Companion | ❌ None | ✅ Pixel pet + TTS voice + shop economy + achievements |

---

## 🏗️ RemindAI's Skill System

RemindAI's Skill System uses a **four-layer architecture**, each with independent storage and lifecycle:

| Layer | Name | Storage | Lifecycle | Description |
|-------|------|---------|-----------|-------------|
| **L1** | Default Meta-Skills | `assets/default_skills/` | Global, shipped with app | ToolShell, Schedule, System — the three core meta-skills forming AI's fundamental capabilities: file I/O, command execution, task planning, environment probing |
| **L2** | User Global Skills | `Skills/` | Global, user-toggled | Imported via ZIP or created with `/skill-cti`; reusable across projects. Format: `SKILL.md` + `tools.json` |
| **L3** | Workspace Temp Skills | `.toolshell/skills/` | Per workspace, always active | AI creates on-demand during guidance; solidifies workflows for the current project; disappears when switching directories — **never pollutes global skills** |
| **L4** | AI Self-Generated Skills 🧪 | (Planned) | Global, not yet implemented for safety | AI auto-generates skills from long-term conversation memory (e.g., if you frequently consult on operations research, AI distills a dedicated OR skill) and invokes it autonomously |

### Design Philosophy

- **L1 Meta-Skills**: The AI's "OS kernel" — file I/O, command execution, environment probing, task scheduling; the foundation of ToolShell
- **L2 Global Skills**: Your "toolbox" — reusable expertise for specific domains, code generation, document templates, workflow automation
- **L3 Temp Skills**: The AI's "sticky notes" — solidify a workflow for the current project, discard cleanly when done. For example, the ToolShell/Schedule/System meta-skill definitions in `memory.json` are injected via the L3 mechanism
- **L4 Self-Generated** (planned): The AI's "long-term learning" — distill domain preferences and working patterns from conversations into personalized skills. **Deferred due to safety concerns around auto-generated executable code**

### Skill Workflows

| Command | Purpose | Destination |
|---------|---------|-------------|
| Direct request to create a skill | Create a project-level skill in current workspace | L3 `.toolshell/skills/` (default) |
| `/skill-temp` | Explicitly create a project-level temp skill | L3 `.toolshell/skills/` |
| `/skill-cti` | Create → Self-test → Install as global skill | Built in `.toolshell/_staging/`, installed to L2 `Skills/` after passing tests |

> 💡 If RemindAI's skills system inspires your projects, papers, or other research, please help me improve and link to the project. This would be very helpful for my graduation and future employment. 🙇‍

---

## 📊 Feature Completion

| Module | Status | Notes |
|---|---|---|
| AI Chat Core (LLM + tool calling) | ✅ | AgentLoop streaming cycle + event-driven UI |
| Controllable AgentLoop Pipeline | ✅ | Think → Write → Test → Verify cyclic pipeline |
| Three LLM Protocols (OpenAI/Anthropic/Gemini) | ✅ | Independent clients, streaming+tools+multimodal |
| ToolShell Meta-Skill | ✅ | read/write/delete/search/exec/python/js + rg/fd/rtk |
| Schedule Meta-Skill | ✅ | 7 tools CRUD + review + archive |
| System Meta-Skill | ✅ | Env probe + sanitized env vars |
| MCP Multi-Transport | ✅ | stdio / SSE / Streamable HTTP |
| Vector Memory | ✅ | Qdrant + SQLite dual-write + auto failover + soft-failure filtering |
| Pluggable Capability | ✅ | Search landed, framework extensible |
| Four-Layer Skill System | ✅ | L1 default meta + L2 user global + L3 workspace temp + L4 planned, batch import support |
| Model Card Management | ✅ | CRUD + logo + drag-sort |
| Multi-Agent Collaboration | ✅ | Framework complete + parallel doc comprehension orchestration + controllable AgentLoop pipeline |
| Domain Experts | ✅ | Preset/custom roles + skill binding |
| Conversation Export | ✅ | MD / PDF / Word / HTML |
| Desktop Experience | ✅ | Tray / notifications / splash / theme animation |
| Global Pet Agent | ✅ | Pixel cat + TTS voice + shop economy + achievements |
| External API Server | ✅ | Built-in HTTP server, three endpoints: OpenAI aggregation / Claude Agent / Claude proxy |
| Online Agent Access | ✅ | Remote access to RemindAI Agent via browser |
| Context Compression | ✅ | RTK Token compression 60-90% + context management optimization |
| Flowchart Summary | ✅ | Use [archify](https://github.com/tt-a1i/archify) to summarize conversations as flowcharts |

---

## 🌟 More Features

| Feature | Description |
|---|---|
| 🐚 ToolShell | File sandbox + Python/Shell/JS exec + rg/fd/rtk + RTK compression 60-90% token savings |
| 🌐 API Server | Built-in HTTP server with three endpoints: OpenAI aggregation, Claude Agent (runs RemindAI's own agent loop), and Claude proxy (pass-through) |
| 🔌 MCP Protocol | stdio/SSE/Streamable HTTP + auto-discovery + drag-and-drop management |
| 🧠 Vector Memory | Qdrant semantic search + SQLite backup + auto-ops + soft-failure filtering + index rebuild |
| 🤝 Multi-Agent | Commander/Worker/Reviewer roles + permission isolation + auto-routing + parallel doc comprehension |
| 🔄 Controllable AgentLoop | Think → Write → Test → Verify cyclic pipeline with long-conversation stutter prevention |
| 🎨 Multi-Model | OpenAI/Anthropic/Gemini native + streaming reasoning chain + multimodal |
| 🧩 Capability | Pluggable architecture, Custom → MCP → ToolShell three-tier routing |
| 📦 Skills | Four-layer architecture (L1 meta / L2 global / L3 temp / L4 self-gen planned), SKILL.md + tools.json format, one-click ZIP import + batch import, command-based creation |
| 🔍 Web Search | Tavily / Brave / Baidu AI Search, session-level toggle |
| 📋 Schedule | SCHEDULE.md driven, P0/P1/P2 priority, AI proactive review |
| 👤 Domain Experts | Preset/custom roles + dedicated system prompts |
| 🖼️ Built-in Tools | Gemini image gen / Formula OCR / PaddleOCR / Flowchart / Rich-text |
| 📊 Flowchart | Use [archify](https://github.com/tt-a1i/archify) to summarize conversations as flowcharts |
| 📤 Export | Markdown / PDF / Word / HTML |
| 🌍 i18n | Full Chinese and English |
| 🎨 Themes | Material 3 light/dark + ripple transition animation |
| 🐱 Global Pet Agent | Pixel cat companion + right-click AI Q&A + Volcano TTS + shop/inventory/feeding + achievements |
| 🗜️ Context Compression | RTK output compression + intelligent conversation context trimming |
| 🌐 Online Access | Remote browser access to Agent with online session management |

### 📦 Bundled CLI Tools

The app ships with these executables — no extra installation needed:

| Tool | Description | Source |
|---|---|---|
| `rg` | [ripgrep](https://github.com/BurntSushi/ripgrep) — blazing fast regex search | BurntSushi/ripgrep |
| `fd` | [fd](https://github.com/sharkdp/fd) — modern file finder | sharkdp/fd |
| `rtk` | [RTK](https://github.com/rtk-ai/rtk) — Token compressor, 60-90% output reduction | nicobailey/rtk |

---

## 🚀 Getting Started

### 📥 Download

Head to [Releases](https://github.com/PythonnotJava/RemindAI/releases) for pre-built packages:

| Platform | Status | Notes |
|---|---|---|
| 💻 Windows | ✅ Officially supported | Installer available |
| 🐧 Linux | 🔧 Build from source | Compiles and runs fine |
| 🍎 macOS | 🔧 Build from source | Compiles and runs fine |

### 🔨 Build from Source

```bash
# Requirements: Flutter SDK >= 3.12.1
git clone https://github.com/PythonnotJava/RemindAI.git
cd RemindAI

# Windows
flutter build windows --release --tree-shake-icons --split-debug-info=./debug-info

# Linux  
flutter build linux --release --tree-shake-icons --split-debug-info=./debug-info
# macOS
flutter create --platforms=macos
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

## Optimization Reference
- [https://arxiv.org/pdf/2606.24775](https://arxiv.org/pdf/2606.24775) — Thanks to this paper for pinpointing a known weakness in memory architectures: the lack of version management leads to retrieval of stale facts.

## Optimization Thoughts
- Is it possible to design a tool paradigm like this: tool name, brief description, version, and documentation URL (so the model can look up unfamiliar tool commands on the fly), allowing the Agent to auto-inject them when relevant?

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
