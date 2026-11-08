# Office Word Engine Protocol v1

所有命令从 stdin（或 `--input`）读一个 JSON 对象，stdout 只输出一个 JSON 响应。  
日志、Python warning、库的 print 全部走 stderr。退出码：`0` 成功，非 `0` 失败。

## 通用响应

成功：

```json
{
  "protocol": 1,
  "status": "ok",
  "engine": "office-word 0.1.0",
  "action": "read"
}
```

失败：

```json
{
  "protocol": 1,
  "status": "error",
  "code": "FILE_NOT_FOUND",
  "message": "文件不存在: ...",
  "hint": "可选提示",
  "details": "可选详情"
}
```

错误码：

| code | 含义 |
|---|---|
| `INVALID_REQUEST` | 请求 JSON/参数不合法 |
| `INVALID_ARGS` | 操作参数不合法 |
| `FILE_NOT_FOUND` | 文件不存在 |
| `UNSUPPORTED_FORMAT` | 不支持的输入格式 |
| `UNSUPPORTED_OUTPUT_FORMAT` | 输出不是 .docx |
| `UNSUPPORTED_OPTION` | 选项未实现（如 track_changes） |
| `UNSUPPORTED_OPERATION` | 未实现的编辑/文件操作 |
| `PARSE_FAILED` | docx 无法解析 |
| `MISSING_DEPENDENCY` | 缺 LibreOffice 等依赖 |
| `CONVERSION_FAILED` | .doc 转换失败 |
| `CONVERSION_TIMEOUT` | .doc 转换超时 |
| `BLOCK_NOT_FOUND` | block_id/table_id 不存在 |
| `TEXT_NOT_FOUND` | 要替换的文本不存在 |
| `STALE_DOCUMENT` | document_hash 不匹配 |
| `CONFIRMATION_REQUIRED` | 永久删除未确认 |
| `VALIDATION_FAILED` | 写出的 docx 无法重新打开 |
| `INTERNAL_ERROR` | 未预期异常 |

---

## `read`

请求：

```json
{
  "action": "read",
  "path": "C:\\Docs\\报告.docx",
  "output_dir": "C:\\Docs\\.toolshell\\office_engine\\报告",
  "options": {
    "mode": "full",
    "include_images": true,
    "max_images": 200,
    "max_chars": 100000
  }
}
```

响应（节选）：

```json
{
  "protocol": 1,
  "status": "ok",
  "engine": "office-word 0.1.0",
  "action": "read",
  "format": "docx",
  "output_dir": "...",
  "document_md": ".../document.md",
  "document_text_md": ".../document.text.md",
  "document_json": ".../document.json",
  "meta_json": ".../meta.json",
  "document_hash": "sha256...",
  "blocks": [
    {"id": "p0", "type": "heading", "level": 1, "text": "标题"},
    {"id": "p1", "type": "paragraph", "text": "正文"},
    {"id": "t0", "type": "table", "rows": [["A", "B"], ["1", "2"]], "header": true},
    {
      "id": "img_001",
      "type": "image",
      "label": "图1",
      "caption": "图1 系统架构",
      "alt": "",
      "path": "images/图1.png",
      "anchor_paragraph_id": "p1",
      "order": 1
    }
  ],
  "images": [
    {"id": "img_001", "label": "图1", "caption": "图1 系统架构", "path": "images/图1.png"}
  ],
  "comments": [
    {
      "id": "213",
      "author": "admin",
      "date": "2026-10-10T09:10:00Z",
      "text": "这个之前的研究应该都有",
      "anchor_block_id": "p18",
      "anchor_text": "（2）将气源采购成本..."
    }
  ],
  "warnings": [],
  "truncated": false,
  "text": "<!-- source: ... -->\n# 标题\n..."
}
```

### block_id 规则

- `p{n}`：`doc.paragraphs[n]`（body 段落，不含表格内段落）
- `t{n}`：`doc.tables[n]`
- `img_{seq:03d}`：按文档流顺序的第 seq 张图片

### 批注

`read` 会解析 `word/comments.xml`，返回 `comments` 数组，并写入 `document.json` 与 Markdown 末尾的 `## Word 批注`。

- `anchor_block_id`：批注锚定的段落/表格 block_id；
- `anchor_text`：锚点文本（表格取首个非空单元格）；
- 支持 `w:commentReference` 和仅 `w:commentRangeStart` 的文档；
- 页眉/页脚中的批注暂不锚定，会写入 `warnings`。

### 输出文件

```text
output_dir/
  document.md
  document.text.md
  document.json
  meta.json
  images/
```

`document.md` 含 `![题注](images/图1.png)`；`document.text.md` 用 `[题注]` 占位。

---

## `create`

请求：

```json
{
  "action": "create",
  "output": "C:\\Docs\\新报告.docx",
  "title": "可选标题",
  "markdown": "# 标题\n\n正文\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n![图1 架构](C:\\Docs\\图1.png)",
  "images": [
    {"path": "C:\\Docs\\图2.png", "caption": "图2 流程"}
  ],
  "options": {"highlight": "none"}
}
```

也可以用 `blocks` 代替 `markdown`：

```json
{
  "output": "...",
  "blocks": [
    {"type": "heading", "level": 1, "text": "标题"},
    {"type": "paragraph", "text": "正文"},
    {"type": "table", "rows": [["A", "B"], ["1", "2"]]},
    {"type": "image", "path": "C:\\Docs\\图1.png", "caption": "图1 架构"}
  ]
}
```

响应：

```json
{
  "status": "ok",
  "action": "create",
  "output": "...",
  "output_format": "docx",
  "document_hash": "sha256...",
  "changes": [],
  "warnings": []
}
```

---

## `edit`

请求：

```json
{
  "action": "edit",
  "source": "C:\\Docs\\报告.docx",
  "output": "C:\\Docs\\报告.edited.docx",
  "document_hash": "sha256...",
  "in_place": false,
  "options": {
    "highlight": "visual",
    "keep_deleted": false
  },
  "operations": [
    {
      "op": "replace_text",
      "block_id": "p12",
      "find": "旧内容",
      "replace": "新内容",
      "occurrence": "first"
    },
    {
      "op": "insert_paragraph_after",
      "block_id": "p12",
      "text": "新增段落",
      "style": "Normal"
    },
    {
      "op": "delete_block",
      "block_id": "p20"
    },
    {
      "op": "set_table_cell",
      "table_id": "t0",
      "row": 1,
      "col": 1,
      "value": "42"
    },
    {
      "op": "insert_image_after",
      "block_id": "p12",
      "path": "C:\\Docs\\图2.png",
      "width_cm": 10,
      "caption": "图2 流程"
    }
  ]
}
```

### 操作

| op | 参数 | 说明 |
|---|---|---|
| `replace_text` | `block_id?`, `find`, `replace`, `occurrence?` | run-aware 替换；跨 run 时合并到起始 run |
| `insert_paragraph_after` | `block_id`, `text`, `style?` | 在段落之后插入 |
| `insert_paragraph_before` | `block_id`, `text`, `style?` | 在段落之前插入 |
| `delete_block` | `block_id` | 删除段落/表格；`keep_deleted` 时段落保留删除线；删除 `（n）` 段落会自动重编号后续连续项 |
| `center_tables` | `table_ids?` | 表格整体水平居中 + 单元格垂直居中 + 单元格文字居中；不传 `table_ids` 处理全部表格 |
| `set_table_cell` | `table_id`, `row`, `col`, `value` | 设置单元格文本 |
| `insert_image_after` | `block_id`, `path`, `width_cm?`, `caption?` | 在段落之后插入图片 |
| `delete_image` | `image_id` | 删除图片（按 read 的 img_001 顺序） |
| `insert_table_row` | `table_id`, `values?` | 追加一行 |
| `delete_table_row` | `table_id`, `row` | 删除一行 |

### 选项

- `highlight`: `none` / `visual`；`track_changes` 返回 `UNSUPPORTED_OPTION`。
- `keep_deleted`: `true` 时删除/替换为空的内容保留红色删除线。
- `in_place`: `true` 覆盖原文件；自动备份 `*.bak-时间戳.docx`。只允许 `.docx`。
- `document_hash`: 可选；不匹配返回 `STALE_DOCUMENT`。

响应：

```json
{
  "status": "ok",
  "action": "edit",
  "source": "...",
  "output": "...",
  "output_format": "docx",
  "document_hash": "sha256...",
  "source_hash": "sha256...",
  "changes": [
    {"op": "replace_text", "block_id": "p12", "before": "...", "after": "..."}
  ],
  "changes_json": ".../报告.edited.changes.json",
  "changes_md": ".../报告.edited.changes.md",
  "warnings": [],
  "backup": null,
  "in_place": false
}
```

---

## `file`

```json
{"action":"file","operation":"info","path":"C:\\Docs\\报告.docx"}
{"action":"file","operation":"delete","path":"C:\\Docs\\报告.docx","mode":"trash"}
{"action":"file","operation":"delete","path":"C:\\Docs\\报告.docx","mode":"permanent","confirm":true}
{"action":"file","operation":"copy","path":"a.docx","dest":"b.docx"}
{"action":"file","operation":"move","path":"a.docx","dest":"b.docx"}
```

- `delete` 默认 `trash`：重命名为 `*.deleted-YYYYMMDD-HHMMSS`，可恢复。
- `permanent` 必须 `confirm=true`。
- `copy`/`move` 目标存在时自动加 `-2`，除非 `overwrite=true`。

---

## `capabilities`

```powershell
python office_word.py capabilities
```

返回支持格式、动作、选项和限制。宿主可以用它做能力探测/版本握手。
