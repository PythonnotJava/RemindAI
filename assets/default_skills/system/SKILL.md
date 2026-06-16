# System — 开发环境探测技能

> 通过读取环境变量和 PATH 探测用户系统中可用的开发工具，让你做出更精准的决策。

## 触发条件

以下情况应主动调用 `system_probe`:
- 首次对话且需要执行命令前（不确定用户装了什么）
- 用户问"我电脑上有什么工具"、"能不能用 xxx"
- 准备调用某个 CLI 工具但不确定是否存在
- 需要选择合适的构建/运行方案时

不需要每次对话都调用。一旦探测过，结果在本次会话内有效。

## 使用策略

1. **首次探测**: 调用 `system_probe` 获取完整环境画像
2. **结果缓存**: 探测结果在会话内有效，不要重复调用
3. **精准决策**: 根据探测结果选择可用的工具链
   - 有 `pnpm` → 优先用 pnpm 而非 npm
   - 有 `rg` → 优先用 ripgrep 而非 findstr/grep
   - 有 `cargo` → 可以直接编译 Rust 项目
   - 无 `docker` → 不要建议容器化方案
4. **降级建议**: 如果缺少关键工具，告知用户并建议安装

## 工具行为

### system_probe

探测系统中可用的开发工具，返回结构化结果。

支持的探测类别:
- `all` — 全量扫描（默认，首次使用）
- `runtime` — 语言运行时 (node, python, java, go, rust, dotnet)
- `package_manager` — 包管理器 (npm, pnpm, yarn, pip, cargo, maven, gradle)
- `vcs` — 版本控制 (git, svn)
- `build` — 构建工具 (cmake, make, msbuild, gradle, flutter)
- `container` — 容器 (docker, podman, kubectl)
- `search` — 搜索工具 (rg, fd, fzf, grep, findstr)
- `editor` — 编辑器 CLI (code, vim, nvim)
- `db` — 数据库工具 (sqlite3, psql, mysql, redis-cli, mongosh)
- `network` — 网络工具 (curl, wget, ssh, openssl)
- `doc` — 文档工具 (pandoc, xelatex, typst)
- `custom` — 按名称探测指定工具

### system_env

读取环境变量。可读取单个变量或列出所有变量。

## 边界

- 只读操作，不会修改系统环境
- 不读取含敏感信息的变量值（API_KEY, TOKEN, SECRET, PASSWORD 等只报告"已设置"不返回值）
- 不访问注册表
- 超时保护: 每个工具探测最多 3 秒
