# 文档办公（file-office）

`file-office` 以内置的 Wisdom.Office（MIT）实现 Office 文档读写，**不需要安装 Office / WPS / pandoc**。入口与其它工具同构：`bin/office-<rid>/file-office[.exe]`。

## 支持矩阵

| 输入 \ 输出 | docx | xlsx | pptx | pdf | md |
|---|---|---|---|---|---|
| docx | ✅ | ✗ | ✅ | ✅ | ✅ |
| xlsx | ✅ | ✅ | ✅ | ✅ | ✅ |
| pptx | ✅（仅文本结构） | ✗ | ✅ | ✅ | ✅ |
| pdf | ✅ | ✗ | ✅ | ✅ | ✅ |
| md | ✅ | ✗ | ✅ | ✅ | ✅ |
| doc / xls | ✗（只读） | ✗ | ✗ | ✗ | ✗ |

- Word / PDF → Excel 不支持：文档模型里没有单元格地址，强行映射会丢语义
- `.doc` / `.xls` 只能作为输入，且 `.xls` 只保留公式缓存值
- PPT → Word 会退化成「一页一段文本」，只适合抽取内容

## 命令

```bash
file-office info    <文件>
file-office text    <文件> [-o out.txt]
file-office md      <文件> [-o out.md] [--keep-images]
file-office convert <输入> <输出>
file-office fill    <模板 docx|xlsx> <vars.json> -o <输出>
```

### info

按内容识别格式并输出 JSON：`format` / `textLength` / `title` / `author` / `creator`，再按类型补充：

- PDF：`pages`、`encrypted`
- 表格：`sheets`、`sheetNames`、`lastRow`
- 演示：`slides`、`slideWidth`、`slideHeight`
- 文档：`sections`、`blocks`

### md

转 Markdown。默认把内联 base64 图片替换成 `![image]`，避免一份需求文档变成 1.3 MB 的文本；需要原图加 `--keep-images`。

### convert

输出格式由**扩展名**决定（`.pdf` / `.docx` / `.xlsx` / `.pptx` / `.md`），输入按**内容**识别。等价命令：

```bash
file-office convert report.docx report.pdf     # Word → PDF
file-office convert sales.xlsx sales.pdf       # Excel → PDF（沿用打印设置）
file-office convert deck.pptx deck.pdf         # PPT → PDF（保留图片）
file-office convert scan.pdf scan.docx         # PDF → Word（重新排版，非像素还原）
file-office convert readme.md readme.docx      # Markdown → Word
```

### fill

模板语法的全部内容：

```
{{key}}                       简单值
{{key:format}}                数字/日期格式，同 Excel
{{obj.prop}}                  点路径（嵌套对象）
{{#each list}} ... {{/each}}  循环，可用 @index / @number / @first / @last / .
```

`vars.json` 顶层必须是对象；数组元素是对象，键即为占位符名。填充值通过字典传入（而不是 POCO），这是 NativeAOT 下能正常工作的前提——反射绑定属性会被裁剪掉。

```json
{
  "customerName": "示例客户",
  "total": 1268.0,
  "items": [{ "name": "无线键盘", "qty": 2 }, { "name": "机械鼠标", "qty": 5 }]
}
```

- 未提供的占位符会被清空（`LeaveUnresolvedTokens = false`），避免 `{{invoiceNo}}` 印在合同上
- 数字格式固定用 `InvariantCulture`，三个平台输出一致
- 表格行循环会复制样式、行高与合并区域；空列表不会留下带 `{{}}` 的残行

## 已知限制

| 限制 | 说明 |
|---|---|
| PDF 中文 | 需要系统里有 TrueType（`glyf`）字体；Linux 容器装 `fonts-noto-cjk`，否则出方块 |
| CFF / OTF 字体 | 不支持嵌入 |
| 加密 PDF | 读取直接失败 |
| 扫描件 | 无 OCR，图片里没有可提取文本 |
| PPT 版式 | 转 Word/PDF 只保留文本与图片位置，SmartArt、动画、母版细节不保证 |
| 大文件 | 95 页图片版 PPT 转 PDF 约 22 MB，注意输出体积 |

## 退出码

- `0`：成功
- `1`：参数错误、文件不存在、格式不支持、转换时抛出异常（stderr 打印 `✗ 类型: 消息`）

数据写 stdout，进度与提示写 stderr，与其它工具一致。
