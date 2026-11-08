# Office 文档元技能

用于读取/生成/修改 Word，以及读取 Excel。底层由 `assets/office_engine` 的 Python 引擎完成；不要让 LLM 临时写 Python 脚本解析办公文件。

## 工具选择

| 场景 | 工具 |
|---|---|
| 读 `.docx` / `.doc` | `office_word_read` |
| 从零生成 `.docx` | `office_word_create` |
| 修改现有 `.docx` | `office_word_edit` |
| Word 文件 info/delete/copy/move | `office_word_file` |
| 读 `.xlsx` / `.xls` | `office_excel_read` |
| Excel 文件 info/delete/copy/move | `office_excel_file` |

**不要**用 `toolshell_read` 直接读 `.docx/.doc/.xlsx/.xls` 二进制文件，也不要用 `toolshell_run_python` + `python-docx/openpyxl` 重新解析；优先用上面的 office 工具。

## Word 读取

- 默认输出到 `.toolshell/office_engine/<文档名>/`；
- 读 `document.md`（含图片链接）或 `document.text.md`（纯文本，图片用题注占位）；
- `document.json` 含 `blocks`、`images`、`comments`、`document_hash`；
- `comments` 是 Word 批注，可用于理解审阅意见；
- 每个段落/表格/图片都有稳定 `block_id`（`p12`、`t0`、`img_001`）。

## Word 修改

- 默认输出新文件，原文件不动；只有用户明确说“直接改原文件”才用 `in_place=true`；
- 修改前先 `office_word_read` 拿 `block_id` 和 `document_hash`，编辑时带上 `document_hash`；
- 用 `block_id` 定位，不要靠模糊文本猜；
- 删除 `（2）...` 这类编号段落会自动把后续 `（3）...` 重编号；
- `center_tables` 会把所有表格整体水平居中 + 单元格垂直居中 + 单元格文字居中；
- 复杂格式（图表、SmartArt、公式、批注）不保证完整保留；优先输出新文件并校验。

## Excel 读取

- 先看 `document.md` 的 sheet 概览、列概览和预览；
- 宽表/大表只给预览，完整数据在 `sheets/*.csv`；
- 需要具体 sheet 时用 `options.sheet`；需要范围时用 `options.range`（必须同时指定 sheet）；
- 公式只读缓存值；`.xls` 没有公式文本/图片/图表；
- 不要用 pandas 重新解析，也不要把 1163 列直接塞进上下文。

## 输出位置

默认都在工作目录的 `.toolshell/office_engine/<文件名>/` 下：

```text
document.md
document.text.md
document.json
meta.json
images/
sheets/*.csv
```

## 失败处理

- `PYTHON_NOT_FOUND`：让用户在工作目录 auto 模式下重试，或手动配置 Python；
- `MISSING_DEPENDENCY`：引擎依赖未安装；
- `STALE_DOCUMENT`：文件已变，重新 `office_word_read`；
- `BLOCK_NOT_FOUND` / `TEXT_NOT_FOUND`：重新读取并用新的 block_id；
- 不要因为一次工具失败就改用 Python 重写整个文件。
