# Office Excel Engine Protocol v1

所有命令从 stdin（或 `--input`）读一个 JSON 对象，stdout 只输出一个 JSON 响应。  
日志、库的 print、Python warning 全部走 stderr。退出码：`0` 成功，非 `0` 失败。

## 通用响应

成功：

```json
{
  "protocol": 1,
  "status": "ok",
  "engine": "office-excel 0.1.0",
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
  "hint": "可选提示"
}
```

错误码：`INVALID_REQUEST` / `INVALID_ARGS` / `FILE_NOT_FOUND` / `UNSUPPORTED_FORMAT` / `PARSE_FAILED` / `SHEET_NOT_FOUND` / `CONFIRMATION_REQUIRED` / `UNSUPPORTED_OPERATION` / `INTERNAL_ERROR`。

---

## `read`

请求：

```json
{
  "action": "read",
  "path": "C:\\Docs\\报表.xlsx",
  "output_dir": "C:\\Docs\\.toolshell\\office_engine\\报表",
  "options": {
    "sheet": "Sheet1",
    "range": "A1:F100",
    "header_row": 1,
    "max_rows": 200,
    "max_cols": 50,
    "max_cells": 20000,
    "max_scan_cells": 1000000,
    "max_csv_rows": 200000,
    "max_formulas": 1000,
    "include_hidden": true,
    "include_formulas": true,
    "include_images": true
  }
}
```

### 选项

| 选项 | 默认 | 说明 |
|---|---|---|
| `sheet` | 全部 | 只读指定 sheet |
| `range` | 全部 | `A1:F100`；必须同时指定 `sheet` |
| `header_row` | `1` | 1-based；`0` 表示无表头，用列字母 |
| `max_rows` | `200` | Markdown/JSON 预览行数 |
| `max_cols` | `50` | Markdown/JSON 预览列数 |
| `max_cells` | `20000` | 预览单元格上限 |
| `max_scan_cells` | `1000000` | 统计扫描上限；超过只扫描预览区 |
| `max_csv_rows` | `200000` | 每个 sheet 的 CSV 行数上限 |
| `max_formulas` | `1000` | JSON 中记录公式数量上限 |
| `include_hidden` | `true` | 是否读取隐藏 sheet/行列 |
| `include_formulas` | `true` | xlsx 是否读公式文本；xls 无公式文本 |
| `include_images` | `true` | xlsx 是否导出图片 |

### 响应

```json
{
  "protocol": 1,
  "status": "ok",
  "engine": "office-excel 0.1.0",
  "action": "read",
  "format": "xlsx",
  "output_dir": "...",
  "document_md": ".../document.md",
  "document_text_md": ".../document.text.md",
  "document_json": ".../document.json",
  "meta_json": ".../meta.json",
  "document_hash": "sha256...",
  "sheets": [
    {
      "name": "Sheet1",
      "rows": 183,
      "columns": 1163,
      "state": "visible",
      "formula_count": 0,
      "columns_meta": [
        {"index": 1, "letter": "A", "header": "用户编号", "type": "string", "nonempty": 182}
      ],
      "merged": [],
      "hidden_rows": [],
      "hidden_cols": [],
      "images": [],
      "csv": "sheets/01-Sheet1.csv",
      "truncated": true
    }
  ],
  "warnings": [],
  "truncated": true,
  "text": "# 工作簿: ..."
}
```

`sheets` 是摘要；完整结构在 `document.json` 的 `workbook.sheets`。

### `document.json` 结构

```json
{
  "source": {
    "path": "...",
    "format": "xlsx",
    "sha256": "...",
    "size": 1649555
  },
  "workbook": {
    "sheet_count": 1,
    "defined_names": [],
    "sheets": [
      {
        "name": "Sheet1",
        "state": "visible",
        "dimensions": "A1:ARS183",
        "rows": 183,
        "columns": 1163,
        "header": ["用户编号", "..."],
        "preview": [["..."]],
        "columns_meta": [],
        "formulas": {"C2": {"formula": "=SUM(B2:B10)", "value": 123.45}},
        "formula_count": 1,
        "merged": ["A6:B6"],
        "tables": [{"name": "Table1", "range": "A1:C10"}],
        "hidden_rows": [5],
        "hidden_cols": ["D"],
        "images": [{"path": "images/01-Sheet1-img01.png", "sheet": "Sheet1", "row": 2, "col": 5}],
        "charts": 0,
        "csv": "sheets/01-Sheet1.csv",
        "truncated": true,
        "warnings": []
      }
    ]
  },
  "warnings": []
}
```

### 单元格规则

- 值：字符串、数字、布尔、日期、错误值；
- 日期：ISO 字符串；午夜日期显示 `YYYY-MM-DD`；
- 公式：`formulas` 中保留 `formula` 和缓存 `value`；
- 空单元格：`null` / CSV 空字符串；
- 不执行公式，只读缓存值。

---

## `file`

```json
{"action":"file","operation":"info","path":"报表.xlsx"}
{"action":"file","operation":"delete","path":"报表.xlsx","mode":"trash"}
{"action":"file","operation":"delete","path":"报表.xlsx","mode":"permanent","confirm":true}
{"action":"file","operation":"copy","path":"a.xlsx","dest":"b.xlsx"}
{"action":"file","operation":"move","path":"a.xlsx","dest":"b.xlsx"}
```

`delete` 默认 `mode=trash`：重命名为 `*.deleted-YYYYMMDD-HHMMSS`，可恢复。  
`permanent` 必须 `confirm=true`。

---

## `capabilities`

```powershell
python office_excel.py capabilities
```

返回支持格式、动作、选项和限制。
