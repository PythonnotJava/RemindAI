# Office Excel Engine (standalone, read-only)

独立于 RemindAI/Flutter 的 Excel 读取引擎。通过 stdin/stdout JSON 协议提供：

| 命令 | 作用 |
|---|---|
| `read` | 读取 `.xlsx` / `.xls`，输出工作簿摘要、Markdown、JSON、每个 sheet 的 CSV |
| `file` | 文件级操作：info / delete / copy / move |
| `capabilities` | 返回支持格式、选项和限制 |

当前只做**读取**，不写回、不修改原文件、不执行公式/宏。

## 目录

```text
assets/office_engine/excel/
  office_excel.py
  excel_engine/
    protocol.py
    reader.py
    utils.py
    cli.py
  tests/
  requirements.txt
  requirements-dev.txt
  README.md
  PROTOCOL.md
```

## 安装

```powershell
cd assets/office_engine/excel
python -m pip install -r requirements.txt
```

运行依赖：`openpyxl`（xlsx）、`xlrd`（xls）、`Pillow`（图片导出）。

## 用法

### 读取

```powershell
'{"path":"C:\\Docs\\报表.xlsx","output_dir":"C:\\Docs\\.toolshell\\office_engine\\报表"}' |
  python office_excel.py read
```

输出：

```text
.toolshell/office_engine/报表/
  document.md          # 工作簿摘要 + 每个 sheet 的列概览/预览
  document.text.md     # 纯文本版（当前与 md 相同）
  document.json        # 结构化工作簿模型
  meta.json            # 源文件、哈希、计数、警告
  sheets/
    01-Sheet1.csv      # 每个 sheet 的完整值
  images/              # xlsx 内嵌图片（可选）
```

### 指定 sheet / 范围

```json
{
  "path": "报表.xlsx",
  "output_dir": "out",
  "options": {
    "sheet": "Sheet1",
    "range": "A1:F100",
    "header_row": 1,
    "max_rows": 200,
    "max_cols": 50
  }
}
```

`range` 必须同时指定 `sheet`，避免对所有 sheet 误用同一范围。

### 文件信息

```json
{"operation":"info","path":"报表.xlsx"}
```

## 设计要点

### 宽表不铺满 Markdown

真实数据里常见 183 行 × 1163 列。`document.md` 只输出：

- 列概览（默认前 `max_cols` 列）；
- 数据预览（默认前 `max_rows` 行 × `max_cols` 列）；
- `完整数据: sheets/xx.csv`。

完整数据始终在 CSV，LLM 需要时再读。

### 公式与缓存值

`.xlsx` 用 openpyxl 加载两次：

- `data_only=False`：读公式文本；
- `data_only=True`：读缓存值。

公式记录：

```json
"C2": {"formula": "=SUM(B2:B10)", "value": 123.45}
```

如果工作簿从未在 Excel 中计算过，缓存值可能为 `null`，会写 warning；预览里用公式文本代替。

### `.xls` 限制

`xlrd` 只能读取：

- 值、日期、布尔、错误值；
- 合并单元格；
- 部分隐藏行列。

不能读取：

- 公式文本；
- 图片、图表；
- 现代样式/条件格式。

`.xls` 读取时会写 warning，说明公式文本不可用。

### 隐藏内容

默认 `include_hidden=true`，隐藏 sheet/行列仍会被读取并在 JSON 标记；设为 `false` 时跳过隐藏 sheet，预览/统计也不含隐藏行列。

### 图片与图表

- `.xlsx` 图片可导出到 `images/`；
- 图表只统计数量并写 warning，不渲染为图片；
- `.xls` 图片/图表不可用。

## 限制

- 只读，不支持写/改/删单元格；
- 不执行公式、不执行宏；
- 图表不渲染；
- 超大文件只扫描 `max_scan_cells` 个单元格，统计可能不完整；
- 超宽 sheet 的列概览只显示前 `max_cols` 列，完整数据在 CSV。

## 测试

```powershell
cd assets/office_engine/excel
python -m unittest discover -s tests -v
```

测试覆盖：xlsx 多 sheet、公式、合并、隐藏行列、图片、宽表截断、sheet/range 过滤、xls 读取、CLI JSON、file info。

`test_read_xls` 需要 `xlwt` 生成测试文件；没有安装时自动跳过：

```powershell
python -m pip install -r requirements-dev.txt
```

## 与 RemindAI 的关系

本目录目前不依赖 RemindAI。后续接入建议：

```text
office_excel_read
office_excel_file
```

Dart 侧用 `Process.start` 调用 `python office_excel.py read`，stdin 写 JSON，stdout 读 JSON。
