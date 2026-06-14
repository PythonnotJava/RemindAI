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

绝对不可操作的路径:
- `.git/` 目录
- `.env` / `.env.*` 文件
- `node_modules/`
- `*.pem` / `*.key` 私钥文件
- 项目根目录之外的任何路径

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
