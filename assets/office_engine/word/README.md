# Office Word Engine (standalone)

独立于 RemindAI/Flutter 的 Word 文档引擎。通过 **stdin/stdout JSON 协议**提供：

| 命令 | 作用 |
|---|---|
| `read` | 读取 `.docx` / `.doc`，输出 Markdown、JSON、图片、批注、稳定 block_id |
| `create` | 从 Markdown 或 blocks 新建 `.docx` |
| `edit` | 修改现有 `.docx`，默认输出新文件 |
| `file` | 文件级操作：info / delete / copy / move |
| `capabilities` | 返回支持格式、选项和限制 |

输出永远是 `.docx`；`.doc` 只作为输入（需要 LibreOffice `soffice`）。

## 目录

```text
assets/office_engine/word/
  office_word.py          # CLI 入口
  word_engine/
    protocol.py           # JSON 协议、错误
    reader.py             # docx 读取、图片、题注、Markdown
    writer.py             # create / edit / file
    legacy.py             # .doc -> .docx (LibreOffice)
    utils.py              # 路径、哈希、原子写入
  tests/
  requirements.txt
  requirements-build.txt
  build.py             # 跨平台构建入口（真正逻辑）
  build.ps1            # Windows wrapper
  build.sh             # macOS / Linux wrapper
  PROTOCOL.md
```

## 安装（开发）

```powershell
cd assets/office_engine/word
python -m pip install -r requirements.txt
```

需要 Python 3.10+。当前环境验证：Python 3.12、python-docx 1.2、Pillow 11.3、lxml 6.0。

## 用法

所有命令都从 stdin 读一个 JSON 请求，stdout 只输出一个 JSON 响应；日志走 stderr。

### 读取

```powershell
'{"path":"C:\\Docs\\报告.docx","output_dir":"C:\\Docs\\.toolshell\\office_engine\\报告"}' |
  python office_word.py read
```

输出目录：

```text
.toolshell/office_engine/报告/
  document.md          # 多模态/UI：含图片链接
  document.text.md     # 纯文本模型：图片用题注占位
  document.json        # 结构化 blocks + images
  meta.json            # 源文件、哈希、引擎版本、警告
  images/
    图1.png
    图2.png
```

### 新建

```json
{
  "output": "C:\\Docs\\新报告.docx",
  "markdown": "# 标题\n\n正文\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n![图1 架构](C:\\Docs\\图1.png)"
}
```

```powershell
python office_word.py create --input create.json
```

### 修改

```json
{
  "source": "C:\\Docs\\报告.docx",
  "output": "C:\\Docs\\报告.edited.docx",
  "document_hash": "从 read 返回的 document_hash",
  "options": {"highlight": "visual", "keep_deleted": false},
  "operations": [
    {"op": "replace_text", "block_id": "p12", "find": "旧内容", "replace": "新内容"},
    {"op": "insert_paragraph_after", "block_id": "p12", "text": "新增段落"},
    {"op": "delete_block", "block_id": "p20"},
    {"op": "set_table_cell", "table_id": "t0", "row": 1, "col": 1, "value": "42"},
    {"op": "insert_image_after", "block_id": "p12", "path": "C:\\Docs\\图2.png", "width_cm": 10}
  ]
}
```

```powershell
python office_word.py edit --input edit.json
```

默认输出新文件，原文件不动。`in_place=true` 才覆盖原文件，并自动备份 `*.bak-时间戳.docx`。

### 文件操作

```json
{"operation":"info","path":"C:\\Docs\\报告.docx"}
{"operation":"delete","path":"C:\\Docs\\报告.docx","mode":"trash"}
{"operation":"copy","path":"a.docx","dest":"b.docx"}
```

`delete` 默认 `mode=trash`（重命名为 `*.deleted-时间戳`，可恢复）；`mode=permanent` 必须 `confirm=true`。

## 设计要点

### 稳定 block_id

`read` 给每个段落/表格/图片分配稳定 ID：

- `p12`：第 12 个 body 段落
- `t0`：第 0 个表格
- `img_001`：第 1 张图片

`edit` 优先用 `block_id` 定位，避免“按文本猜段落”改错。  
`read` 返回 `document_hash`；`edit` 带上它，文件被外部改动时返回 `STALE_DOCUMENT`。

### 图片与题注

- 优先用 Word 题注（`Caption` 样式或 `图1` / `Figure 1` 正则）命名；
- 没有题注时用 `图001` 顺序号；
- 图片按文档流顺序提取，不按 `word/media` 文件名；
- 支持 DrawingML 和旧式 VML 图片；
- 相同图片按 SHA-256 去重；
- 图片统一缩放/转 PNG/JPEG；EMF/WMF/SVG 转换失败时保留原文件并写 warning。

### 两套 Markdown

- `document.md`：`![图1 题注](images/图1.png)`，给多模态/UI；
- `document.text.md`：`[图1 题注]`，给纯文本模型。

注意：**图片路径不等于模型能看到图**。宿主需要把图片作为 image content parts 注入模型；本引擎只负责提取和落盘。

### 批注

`read` 会解析 `word/comments.xml`，把批注放在 `document.json` 的 `comments` 和 Markdown 末尾的 `## Word 批注`：

```json
{
  "id": "213",
  "author": "admin",
  "date": "2026-10-10T09:10:00Z",
  "text": "这个之前的研究应该都有",
  "anchor_block_id": "p18",
  "anchor_text": "（2）将气源采购成本..."
}
```

批注锚点优先用 `w:commentReference`，并兼容只有 `w:commentRangeStart` 的文档；表格内批注会锚到 `tN`。  
这样 Agent 可以先读批注，再决定删/改/补哪里。当前只支持读取批注，不支持新增/删除/回复。

### 自动编号

`delete_block` 删除 `（2）...` 这类段落时，会自动把后续连续的 `（3）...` 重编号为 `（2）...`，直到遇到非编号段落/标题。  
返回的 `changes[].renumbered` 会记录 `old/new/text`。

### 表格居中

`edit` 支持：

```json
{"op": "center_tables"}
```

会同时设置：

- `table.alignment = CENTER`（表格整体水平居中）；
- 每个单元格 `vertical_alignment = CENTER`（上下居中）；
- 单元格内段落 `alignment = CENTER`（左右居中）。

也可以用 `table_ids: ["t0", "t2"]` 只处理指定表格。

### 高亮

- `highlight=visual`：新增/替换文字黄色高亮；`keep_deleted=true` 时删除内容红色删除线；
- `highlight=track_changes`：**未实现**，会返回 `UNSUPPORTED_OPTION`；
- 真正的 Word 修订（`w:ins` / `w:del`）需要后续 XML/LibreOffice UNO 支持。

### 变更记录

`edit` 会生成：

```text
报告.edited.changes.json
报告.edited.changes.md
```

包含每个操作的 before/after，方便审查。

## 限制（MVP）

- 不支持真正的 Word 修订；批注只读，不支持新增/删除/回复；
- 不支持复杂图表、SmartArt、公式、文本框的完整编辑；
- 表格合并单元格在 Markdown 中可能丢失结构；
- `python-docx` 保存复杂文档时可能丢失它不支持的格式；
- `.doc` 需要 LibreOffice；没有则 `MISSING_DEPENDENCY`；
- 图片在页眉/页脚、表格单元格中的提取尚未完整覆盖；
- 没有实现长驻服务模式，每次调用启动一个进程。

## 测试

```powershell
cd assets/office_engine/word
python -m unittest discover -s tests -v
```

当前覆盖：读取、图片/题注、Markdown、创建、替换/插入/删除/表格、stale hash、文件 info/trash、CLI JSON。

## 打包（Windows / macOS / Linux）

`build.py` 是跨平台入口；`build.ps1` / `build.sh` 只是各自平台的 wrapper。

### Windows

```powershell
cd assets/office_engine/word
powershell -ExecutionPolicy Bypass -File build.ps1
```

生成 `dist\office_word.exe`。

### macOS / Linux

```bash
cd assets/office_engine/word
chmod +x build.sh
./build.sh
```

生成 `dist/office_word`（macOS/Linux 无 `.exe` 后缀）。

### 直接用 Python（三个平台都一样）

```bash
python build.py
python build.py --onedir
python build.py --outdir ../windows-x64
```

`--onedir` 启动更快、杀软误报更少；`--onefile` 分发简单但每次启动会解压。正式分发建议代码签名；macOS 还需要 notarization。

### 不能交叉编译

PyInstaller 只能构建当前平台的可执行文件。要同时发布 Windows/macOS/Linux，必须在对应系统上分别构建，或用 CI matrix（例如 GitHub Actions 的 `windows-latest` / `macos-latest` / `ubuntu-latest`）。

### 运行权限

- Windows：直接运行 `.exe`。
- macOS/Linux：需要可执行位：
  ```bash
  chmod +x dist/office_word
  ```
- 如果从 Flutter assets 复制出来运行，也要在复制后 `chmod +x`；macOS 还需要对嵌套二进制签名。

## 与 RemindAI 的关系

本目录目前**不依赖 RemindAI**，也不修改 Flutter 代码。后续接入时只需要：

1. 定位 `office_word.exe`；
2. `Process.start`，stdin 写 JSON；
3. 解析 stdout JSON；
4. 把 `office_word_read/create/edit/file` 暴露为 Agent 工具。

对应工具命名建议：

```text
office_word_read
office_word_create
office_word_edit
office_word_file
```
