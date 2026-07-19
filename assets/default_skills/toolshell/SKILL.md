# ToolShell - 大模型工具外壳技能

> 当此技能激活时，你将获得受控的文件操作、Shell命令执行和持久记忆能力。

## 触发条件

当项目根目录存在 `memory.json` 时自动激活，或用户明确要求使用 ToolShell 模式。

## 启动流程

激活后你必须按顺序执行:

1. 读取项目根目录的 `memory.json`，解析配置
2. 确定操作模式 (MODE)、记忆策略 (MIND/REMIND)
3. 如果 REMIND=true，在 `.toolshell/memory.db` 中检索相关历史记忆
4. 将记忆注入当前上下文，开始工作

## 配置字段

从 `memory.json` 读取:

| 字段 | 值 | 含义 |
|------|-----|------|
| MODE | "normal" | 每次文件操作/命令执行前向用户确认 |
| MODE | "auto" | 完全自主，直接执行所有操作 |
| REMIND | true/false | 任务开始前是否召回历史记忆 |
| MIND | true | 长期记忆: 跨会话持久存储 |
| MIND | false | 短期记忆: 仅当前会话有效 |

## 操作模式行为

### normal 模式

每次执行破坏性操作前，必须按以下格式确认:

```
[ToolShell] 操作: WRITE → src/main.dart (新建, 42行)
是否执行? [y/N/always]
```

用户回复:
- y → 执行本次
- N → 跳过
- always → 本会话切换为 auto 模式

### auto 模式

所有操作直接执行，无需确认。但仍遵守安全边界。

## 安全边界 (两种模式均生效)

### 绝对禁止操作的路径
- `.git/` 目录（保护版本控制完整性）
- `.env` / `.env.*` 文件（保护敏感凭证）
- `node_modules/`（避免破坏依赖）
- `*.pem` / `*.key` 私钥文件（保护密钥安全）

### 跨目录操作
**允许**读取和操作工作目录之外的路径（例如读取其他项目文件、访问用户文档等），但：
- **写入/删除/执行**操作在 normal 模式下会触发权限确认
- auto 模式下跨目录的破坏性操作直接执行，请谨慎使用

跨目录场景示例：
- 读取另一个项目的配置文件
- 分析用户桌面上的文档
- 备份文件到其他目录

## 技能去向决策（创建技能前必读）

当用户要求"做一个技能 / 写个 skill / 固化某流程"时，先判断技能该落在**项目级**还是**全局**，规则如下，**不要自作主张往全局装**：

| 用户怎么说 | 技能去向 | 落点 |
|---|---|---|
| **直接**要求做技能（没说任何命令） | **项目级**（默认） | `.toolshell/skills/<技能名>/` |
| 消息以 `/skill-temp` 开头 | **项目级**（显式） | `.toolshell/skills/<技能名>/` |
| 消息以 `/skill-cti` 开头 | **全局** | 先 `.toolshell/_staging/` 搭建测试，再装到 `Skills/` |

核心原则：
- **默认局部**。用户没有显式说"装到全局 / 复用到所有项目 / `/skill-cti`"时，一律建在 `.toolshell/skills/`，只在当前工作目录生效，**绝不**调用 `toolshell_install_skill` 往全局装。
- 只有用户**显式**表达"全局可复用"意图或使用 `/skill-cti` 命令时，才走全局安装流程。
- 拿不准时按局部处理，并可一句话告知用户"已建为项目技能，如需全局复用可用 /skill-cti"。

## 项目级临时技能 (.toolshell/skills/)

当你需要为**当前工作目录**创建一个专属的、可复用的技能时（例如把一段常用流程固化成工具，或为这个项目沉淀一套操作规范），按以下约定放置，应用会在下次构建上下文时自动加载：

```
<工作目录>/.toolshell/skills/<技能名>/
    SKILL.md       # 必需：技能说明与使用指南（会注入到系统提示词）
    tools.json     # 可选：自定义工具定义（OpenAI function 格式）
```

规则：
- **必需** `SKILL.md`，缺失则该目录不会被识别为技能
- `tools.json` 可选；若提供，其中声明的工具会一并注册，仍通过 toolshell 执行并受权限约束
- 这类技能**只在所属工作目录下生效**，恒定处于激活状态，无需用户在技能页手动启用
- 切换到其他工作目录后自动消失，不影响全局技能
- 不要把项目技能放到其他位置（如工作目录根、随意命名的文件夹）——只有 `.toolshell/skills/` 会被扫描

创建技能后，告知用户该技能已就绪、将在新对话或下一轮上下文构建时自动加载。

## /skill-temp 工作流 (创建项目级技能)

当用户消息以 `/skill-temp` 开头时（后面跟着对所需技能的描述），在**当前工作目录**创建一个项目级技能，**不**装到全局：

1. 在 `.toolshell/skills/<技能名>/` 用 `toolshell_write` 写入 `SKILL.md`（必需，写清用途、触发条件、使用指南）；若需要自定义工具，再按 OpenAI function 格式写 `tools.json`（可选）。
2. 若技能含可执行逻辑，可用 `toolshell_run_python` / `toolshell_run_js` / `toolshell_exec` 跑个最小用例自测。
3. 告知用户：该技能已建为**项目级技能**，仅在当前工作目录生效、恒定激活、跟随工作目录，下一轮上下文构建时自动加载；如需提升为全局可复用技能，可用 `/skill-cti`。

**不要**对 `/skill-temp` 的产物调用 `toolshell_install_skill`——它就该留在工作目录里。


## /skill-cti 工作流 (创建·测试·安装到全局)

当用户消息以 `/skill-cti` 开头时（后面跟着对所需技能的描述），按以下三步闭环执行，目标是产出一个**全局可复用**的技能：

### 1. 创建 (Create)

在工作目录下的 **staging 目录** `.toolshell/_staging/<技能名>/` 搭建技能骨架：
- `SKILL.md`（必需）：清晰写明技能用途、触发条件、使用指南
- `tools.json`（可选）：若技能需要自定义工具，按 OpenAI function 格式声明

用 `toolshell_write` 写入这些文件。

> 为什么用 `.toolshell/_staging/` 而**不是** `.toolshell/skills/`？
> `.toolshell/skills/` 会被扫描成"项目级临时技能"并恒定激活——若把 /skill-cti 的产物放那里，
> 它既会作为项目技能加载、装到全局后又会作为全局技能加载，造成**双重加载**（工具名注册两遍）。
> `_staging` 不会被扫描，纯粹用于搭建/自测；装到全局后该目录会被自动清理。

### 2. 测试 (Test)

安装到全局**之前**必须自测，确认技能可用：
- 校验 `SKILL.md` 内容完整、`tools.json`（若有）为合法 JSON
- 若技能含可执行逻辑，用 `toolshell_run_python` / `toolshell_run_js` / `toolshell_exec` 跑一个最小用例验证
- 自测失败则修正后重测，**不要**带着已知问题安装

### 3. 安装到全局 (Install)

自测通过后，调用 `toolshell_install_skill`，把 staging 技能目录提升为**全局技能**：

```
toolshell_install_skill(source_dir="<staging 技能目录绝对路径>", name="<技能名>")
```

- 全局技能落在应用的 `Skills/` 目录，**不是** `.toolshell/`
- 安装后该技能出现在技能页，由用户自行开关，可在任意工作目录复用
- 安装成功后 `.toolshell/_staging/<技能名>/` 会被**自动清理**，不在工作目录留副本
- 安装成功后告知用户技能名、用途，并提示可在技能页管理与开关

注意区分两类技能去向：
- **仅本目录长期使用的项目规范** → 放 `.toolshell/skills/`（项目级，跟随工作目录，恒定激活）
- **沉淀为全局可复用能力**（/skill-cti 的目标）→ 在 `.toolshell/_staging/` 搭建并自测，再用 `toolshell_install_skill` 装到全局 `Skills/`，由用户开关

## 记忆系统

### 存储位置

项目根目录下 `.toolshell/memory.db` (SQLite)

### 何时存储记忆

主动识别并存储以下信息:
- **fact**: 用户陈述的事实、项目约定、技术选型
- **decision**: 做出的决策及原因
- **context**: 项目背景、架构信息
- **error**: 踩过的坑、失败的方案
- **outcome**: 任务完成结果

### 重要性评分

- 0.8~1.0: 核心架构决策、用户强调的偏好
- 0.5~0.7: 一般性上下文、中等重要的事实
- 0.1~0.4: 临时信息、琐碎细节

判断标准: 这条信息6个月后还有价值吗? 是 → ≥0.7

### 何时召回记忆

- REMIND=true 时，每次新任务开始前自动召回
- 用户问"之前我们做过什么"时主动召回
- 遇到可能有历史决策的问题时主动召回

### 向量检索 (可选)

如果 `memory.json` 提供了以下三个字段且 API 可达:
- QDRANT_EMBED_MODEL_URL
- QDRANT_EMBED_MODEL_KEY  
- QDRANT_EMBED_MODEL_NAME

则存储记忆时同时生成向量嵌入，召回时使用语义相似度排序。
否则使用 SQLite 关键词匹配。

## 工具使用指南

你已有的工具 (Read/Write/Bash等) 在此技能下的使用规范:

### 文件读取
正常使用 Read 工具。记录读取过的关键文件路径到记忆。

### 文件写入
- normal 模式: 先展示变更内容，确认后写入
- auto 模式: 直接写入

### 命令执行
- 使用 Bash 工具执行 Shell 命令
- 长时间命令 (build, install) 提醒用户可能需要等待
- 命令失败时存储错误信息到记忆 (type=error)

### 文件删除
- normal 模式: 必须确认
- auto 模式: 直接执行，但记录到记忆

## 会话结束

会话结束时:
- 如果 MIND=true: 记忆保留
- 如果 MIND=false: 生成本次会话摘要存为一条 fact，清除其他记忆

## Python 代码执行

使用 `toolshell_run_python` 工具可以直接执行 Python 代码。

### 行为规则（必须遵守）

当用户要求"画图"、"绘制"、"用matplotlib"、"运行Python"、"执行代码"、"数据分析"、"可视化"等涉及 Python 运行的需求时：
1. **必须**调用 `toolshell_run_python` 工具实际执行代码
2. **禁止**仅输出代码文本让用户自行运行
3. 执行后根据返回的 `images` 和 `stdout` 组织回复
4. 纯文本输出（如计算结果）直接引用 `stdout` 内容展示
5. 有图片时用 Markdown 图片语法 `![描述](图片路径)` 嵌入回复

### 图片自动捕获

工具会自动拦截 `plt.show()` 和 `plt.savefig()` 调用，将图片保存为 PNG 文件。
返回结果中 `images` 字段包含生成的图片路径列表。

### 在回复中展示图片

当 `images` 不为空时，**必须**在回复中用 Markdown 图片语法展示:

```
![图表描述](file:///C:/Users/.../fig_1.png)
```

### 返回格式

```json
{
  "status": "ok",
  "exit_code": 0,
  "stdout": "程序输出...",
  "stderr": "",
  "images": ["C:/Users/.../fig_1.png", "C:/Users/.../fig_2.png"],
  "truncated": false
}
```

### 注意事项
- matplotlib 使用 Agg 后端（无窗口弹出）
- 无需手动 `plt.savefig()`，直接 `plt.show()` 即可自动保存
- 需要系统已安装 Python 及所需库（matplotlib 等）
- 代码在项目根目录下执行
- 执行需用户确认（normal 模式）

## 并行子调用 (toolshell_run_parallel)

当一次决策中需要发起**多个互不依赖**的只读/查询类调用时（例如同时读取几个不同文件、同时按不同模式搜索），使用 `toolshell_run_parallel` 一次性并发发起，而不是逐个串行调用等待。

### 使用方式

```json
{
  "calls": [
    {"tool": "toolshell_read", "args": {"path": "a.txt"}},
    {"tool": "toolshell_read", "args": {"path": "b.txt"}},
    {"tool": "toolshell_search", "args": {"pattern": "*.dart"}}
  ]
}
```

### 限制（必须遵守）

- 单批最多 8 个子调用，超出会被整体拒绝(`TOO_MANY_CALLS`)
- **只用于只读/查询类工具**（如 `toolshell_read`、`toolshell_search`、`toolshell_memory_recall` 等）
- 批次中若包含任意写/删/执行/跑代码类工具（`toolshell_write`/`toolshell_delete`/`toolshell_exec`/`toolshell_run_python`/`toolshell_run_js`），或再次嵌套 `toolshell_run_parallel`，整批会被直接拒绝(`PARALLEL_NOT_ALLOWED`)——这是因为并发写同一资源、并发弹出多个权限确认框存在竞态和体验问题。遇到这类需求，请改为逐个串行调用。
- 参数缺失或格式不对（如 `calls` 不是数组、某项缺少 `tool` 字段）会被拒绝(`INVALID_ARGS`)

### 返回格式

```json
{
  "status": "ok",
  "count": 3,
  "results": [
    {"tool": "toolshell_read", "args": {...}, "result": {...}},
    {"tool": "toolshell_read", "args": {...}, "result": {...}},
    {"tool": "toolshell_search", "args": {...}, "result": {...}}
  ]
}
```

单个子调用异常不会中断整批，会在对应结果项中以 `error` 字段体现。

## Worktree 隔离 (实验性修改不污染主工作区)

当你要做的改动**探索性强、可能失败、或影响面较大**（大范围重构、尝试一个不确定的实现方案、升级有兼容风险的依赖等），可以先开一个隔离的 Git 工作树，把改动限制在里面，验证通过再合并回主分支，不满意就直接丢弃——不会弄乱用户当前看到的主工作目录。

**这是默认能力，不需要任何配置开启**。是否使用、什么时候用，完全由你自己判断；框架不会自动检测"风险操作"并强制你进入隔离模式，也不会在你没调用工具时静默切换目录。

### 前提条件

工作目录必须是一个 git 仓库(有 `.git`)。不是的话调用会返回 `NOT_GIT_REPO`，可先用 `toolshell_exec` 执行 `git init`（如果用户希望这么做）。

### 使用方式

1. **开始隔离**：调用 `toolshell_worktree_start(name="简短描述")`。成功后会新建分支 `toolshell-wt/<name>_<时间戳>`，工作树落在 `<工作目录>/.toolshell/worktrees/<name>_<时间戳>/`。**从这次调用之后，你的所有 `toolshell_read`/`toolshell_write`/`toolshell_exec` 等操作都会自动定向到这个隔离工作树**，不需要你手动拼接路径或切换 cwd。

2. **正常工作**：在隔离状态下按平时的方式操作文件、跑命令、测试——效果和平时完全一样，只是发生在隔离的工作树里。

3. **结束隔离**：
   - 满意了 → `toolshell_worktree_finish(action="merge")`：自动提交工作树里的未保存改动，合并回主分支，清理工作树和分支。若主工作目录此时有未提交的改动，会拒绝合并(避免冲突)并提示你先处理，工作树内容不会丢失。
   - 不满意 → `toolshell_worktree_finish(action="discard")`：直接丢弃工作树和分支，改动全部消失，主工作目录完全不受影响。

结束后自动恢复对主工作目录的正常操作，不需要额外操作。

### 注意事项

- 同一时间只支持一个活跃的隔离工作树；开始新的隔离前应先结束上一个。
- 隔离工作树位于 `.toolshell/worktrees/` 下，属于框架内部约定目录，不要把它当作可长期存放代码的地方——它是临时的，merge/discard 后就没了。
- 隔离期间用户在界面上看到的"当前工作目录"不会改变(只是内部执行落点变了)；完成后主动告知用户你做了哪些改动、是否已合并。
