<div align="center">
  <img src="snapshots/logos/logo_egg.png" alt="RemindAI Logo" width="128" />
  <h1>🧠 RemindAI</h1>
  <p><strong>开源桌面 AI 助手 — 不只是对话，而是真正的工具外壳</strong></p>
  <p>
    <a href="./README_EN.md">🌐 English</a> |
    <a href="https://github.com/PythonnotJava/RemindAI/releases">📦 下载</a> |
    <a href="#-快速开始">🚀 快速开始</a>
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
  <img src="snapshots/results_promotion.png" alt="RemindAI 效果展示" width="900" />
</p>

---

## 💡 这是什么

RemindAI 是一个**开源桌面 AI 助手**，核心理念是为大模型提供一层完整的**工具外壳 (ToolShell)**，让 AI 不仅能聊天，还能直接操作文件、执行代码、调用外部工具、管理记忆，成为真正的生产力工具。

> 🎯 一句话：**把 AI 从聊天框里释放出来，给它一个操作系统。**

### 🆚 与普通 AI 客户端的区别

| | 🔵 普通 AI 客户端 | 🟣 RemindAI |
|---|---|---|
| 📁 文件操作 | ❌ 不支持或需插件 | ✅ 内置沙盒文件系统 |
| 💻 代码执行 | ❌ 不支持 | ✅ 内置 Python/Shell 执行器 |
| 🧠 记忆 | ❌ 无或仅上下文 | ✅ 向量语义记忆 + SQLite 持久化 |
| 🔌 工具扩展 | ⚠️ 有限 | ✅ MCP 协议 + 技能系统 + Capability 插件 |
| 🤝 多 Agent | ⚠️ 多窗口并排 | ✅ 真协作：指挥部广播、权限隔离、自动路由 |

---

## 📊 功能完成度

| 模块 | 状态 | 说明 |
|---|---|---|
| AI 对话核心 (LLM + tool calling) | ✅ | AgentLoop 流式循环 + 事件驱动 UI |
| 三端 LLM 适配 (OpenAI/Anthropic/Gemini) | ✅ | 各自独立客户端，流式+tool_call+多模态 |
| ToolShell 元技能 | ✅ | 读/写/删/搜索/exec/python + rg/fd/rtk |
| Schedule 元技能 | ✅ | 7 工具 CRUD + 审查 + 归档 |
| System 元技能 | ✅ | 环境探测 + 环境变量脱敏 |
| MCP 多传输 | ✅ | stdio / SSE / Streamable HTTP |
| 向量记忆系统 | ✅ | Qdrant + SQLite 双写 + 自动容灾 |
| 可插拔 Capability | ✅ | 搜索能力已落地，框架可扩展 |
| 技能系统 | ✅ | ZIP 导入 / 排序 / 激活 |
| 模型 Card 管理 | ✅ | 增删改 + Logo + 拖拽排序 |
| 多 Agent 协作 | ⚡ | 框架已搭建，执行链路持续完善中 |
| 领域专家系统 | ✅ | 预设/自定义角色 + 绑定技能 |
| 对话导出 | ✅ | MD / PDF / Word / HTML |
| 桌面体验 | ✅ | 托盘 / 通知 / 闪屏 / 主题动画 |
| 全局宠物 Agent | ✅ | 像素猫 + TTS 语音 + 商店经济 + 成就系统 |

---

## 🌟 更多特性

| 特性 | 说明 |
|---|---|
| 🐚 ToolShell | 文件沙盒 + Python/Shell 执行 + rg/fd/rtk + RTK 压缩 60-90% token |
| 🌐 对外 API 服务 | 内置 HTTP 服务器，三种端点：OpenAI 聚合、Claude Agent（运行 RemindAI 自身的 AgentLoop）、Claude 代理（纯透传） |
| 🔌 MCP 协议 | stdio/SSE/Streamable HTTP 三传输 + 工具自动发现 + 拖拽管理 |
| 🧠 向量记忆 | Qdrant 语义搜索 + SQLite 持久备份 + 自动运维 + 记忆重建 |
| 🤝 多 Agent | 指挥部/工作者/审查员角色 + 权限隔离 + 自动路由 |
| 🎨 多模型 | OpenAI/Anthropic/Gemini 原生适配 + 流式推理链 + 多模态 |
| 🧩 Capability | 可插拔能力架构，Custom → MCP → ToolShell 三级路由 |
| 📦 技能系统 | SKILL.md + tools.json 格式，ZIP 一键导入 |
| 🔍 Web 搜索 | Tavily / Brave / 百度智能搜索，会话级开关 |
| 📋 Schedule | SCHEDULE.md 驱动，P0/P1/P2 优先级，AI 主动回顾 |
| 👤 领域专家 | 预设/自定义角色 + 独立 system prompt |
| 🖼️ 内置工具 | Gemini 文生图 / 公式 OCR / PaddleOCR / 流程图 / 富文本 |
| 📤 导出 | Markdown / PDF / Word / HTML |
| 🌍 国际化 | 完整中英双语 |
| 🎨 主题 | Material 3 亮/暗 + 涟漪切换动画 |
| 🐱 全局宠物 Agent | 像素猫陪伴 + 右键智能问答 + 火山TTS语音 + 商店/背包/投喂 + 成就系统 |

### 📦 内置 CLI 工具

应用自带以下可执行文件，无需用户额外安装：

| 工具 | 说明 | 来源 |
|---|---|---|
| `rg` | [ripgrep](https://github.com/BurntSushi/ripgrep) — 极速正则搜索 | BurntSushi/ripgrep |
| `fd` | [fd](https://github.com/sharkdp/fd) — 现代化文件查找 | sharkdp/fd |
| `rtk` | [RTK](https://github.com/rtk-ai/rtk) — Token 压缩器，减少 60-90% 命令输出 token | nicobailey/rtk |

---

## 🚀 快速开始

### 📥 下载

前往 [Releases](https://github.com/PythonnotJava/RemindAI/releases) 下载预编译包：

| 平台 | 状态 | 说明 |
|---|---|---|
| 💻 Windows | ✅ 正式支持 | 提供安装包 |
| 🐧 Linux | 🔧 自行编译 | 源码构建即可使用 |
| 🍎 macOS | 🔧 自行编译 | 源码构建即可使用 |

### 🔨 从源码构建

```bash
# 环境要求: Flutter SDK >= 3.12.1
git clone https://github.com/PythonnotJava/RemindAI.git
cd RemindAI

# Windows
flutter build windows --release --tree-shake-icons --split-debug-info=./debug-info

# Linux / macOS
flutter build linux --release --tree-shake-icons --split-debug-info=./debug-info
flutter build macos --release --tree-shake-icons --split-debug-info=./debug-info
```

---

## 🖼️ 截图

<details>
<summary>📸 点击展开</summary>

| 功能 | 截图 |
|---|---|
| 🏠 主界面 | <img src="snapshots/main_page.png" width="600" /> |
| 📁 工作目录 | <img src="snapshots/work_dir.png" width="600" /> |
| 🔌 MCP 服务 | <img src="snapshots/mcp_support.png" width="600" /> |
| 🧠 记忆系统 | <img src="snapshots/memory_use.png" width="600" /> |
| 🤝 多 Agent | <img src="snapshots/muti_agents.jpg" width="600" /> |
| 📦 技能系统 | <img src="snapshots/skill_support.png" width="600" /> |

</details>

---

## 🙏 致谢 

感谢 **Yu** 为 RemindAI 设计了精巧灵动的 Logo，为产品注入了鲜活的生命力。

---

## ☕ 赞助

如果 RemindAI 对你有帮助，欢迎选择性赞助支持开发 ~

<p align="center">
  <img src="snapshots/sponsor/wechat.jpg" alt="微信赞赏" width="200" />
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
  <img src="snapshots/sponsor/alipay.jpg" alt="支付宝赞赏" width="200" />
</p>
<p align="center">
  <sub>💚 微信 &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; 🔵 支付宝</sub>
</p>

---

## 📄 许可证

[MIT License](./LICENSE) — Copyright (c) 2026 PythonnotJava

<div align="center">
  <sub>用 Flutter 和热情构建 ❤️</sub>
</div>
