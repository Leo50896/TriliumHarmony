# 原生电子表格（ArkUI）

## 1. 目标

spreadsheet 笔记不再进入 WebView/Luckysheet，而是由 ArkUI 原生组件渲染：

```text
EditorView
  └── NativeSheetView
        └── SheetParser: Univer JSON -> SheetCell[][]
```

这样可以彻底避免 WebView 字体回退、主题冲突和库体积。

## 2. SheetParser

输入 Trilium 的 `{ version, workbook }` JSON，兼容直接 `IWorkbookData`。

输出：

```ts
class SheetCell {
  value: string;
  bg: string;
  fc: string;
  bold: boolean;
  fontSize: number;
  wrap: boolean;
  rowSpan: number;
  colSpan: number;
  covered: boolean;
}

class ParsedSheet {
  cells: SheetCell[][];
  rows: SheetRow[];
  columnWidths: number[];
  rowHeights: number[];
  columnLabels: string[];
  rowLabels: string[];
}
```

解析规则：

- `workbook.styles` + `cell.s`（样式 ID 或内联对象）→ `bg/fc(cl)/bl/fs/tb`；
- 没有样式：`bg=#1E1F22`、`fc=#CCCCCC`、`fs=13`；
- `tb`：Univer `1 overflow / 2 clip / 3 wrap`；`3` 才设置 `wrap=true`；
- 首行强制 `#2D2D30` / `#FFFFFF` / bold；
- `n.pattern` 日期数字格式化为 `yyyy-MM-dd hh:mm:ss`；
- `SHEET_DATA_VALIDATION_PLUGIN` 解析 list options 与 `formula2` 颜色，生成静态标签色；
- `mergeData` 写入 `rowSpan/colSpan`，被覆盖格标记 `covered=true` 并清空内容；
- `maxUsedRow/maxUsedCol` 只统计真实有值单元格；
- `rowCount = maxUsedRow + 2`，`colCount = maxUsedCol`，不渲染大块空网格。

## 3. NativeSheetView 布局

```text
Column（内容自适应）
├── Row（表格内容）
│   ├── Column（行号区）
│   └── Scroll（横向）
│       └── Column
│           ├── Row（A/B/C 列标）
│           └── Grid（包含首行在内的全部数据）
└── 60vp 底部占位
```

- 列标/首行数据与 Grid 共用横向 Scroll，天然对齐；
- 表格没有内部纵向滚动，纵向完全交给外层笔记页；
- 左侧行号与数据行高度一一对应；
- 超过 50 行时使用 `LazyForEach` + `IDataSource`；
- 多 Sheet：`workbook.sheetOrder` 驱动底部 Tab；`SheetParser.parse(source, sheetIndex)` 按页解析；
- Sheet Tab 由 `EditorView` 的根 `Stack` 覆盖在屏幕底部，不属于表格滚动内容；
- `rowData.hd / isHidden / hidden` 只解析不应用，始终渲染全量行；
- `GridItem` 使用 `right/bottom` 1vp 网格线，选中时改为 2vp 蓝色边框；
- 列标、行号、首行数据表头同样绘制网格线；
- 表头也通过 `onClick` 选中，`selectedRow=0` 时显示蓝色边框；
- 表格高度自适应内容，不设置固定高度；
- 纵向完全由外层笔记页 Scroll 处理，表格内部不产生纵向滚动条；
- 横向滚动仍由表头/数据共用的横向 Scroll 承担；
- Sheet Tab 在 `EditorView` 根 Stack 中悬浮于屏幕底部，不属于表格滚动内容；
- `@StorageProp('colorMode')` 监听系统明暗模式，表头/网格/单元格颜色由 `sheet_*` 资源驱动；

## 4. 单元格

```ts
Text(cell.value)
  .fontSize(cell.fontSize)
  .fontColor(cell.fc)
  .fontWeight(cell.bold ? FontWeight.Bold : FontWeight.Normal)
  .maxLines(cell.wrap ? 3 : 1)
  .textOverflow({ overflow: TextOverflow.Ellipsis })
  .backgroundColor(cell.bg)
  .border({ width: selected ? 2 : 0, color: '#0A84FF' })
```

- 不设置 `fontFamily`，直接继承 ArkUI 系统字体；
- 点击记录 `(row, col)`，对应 `GridItem` 添加蓝色边框；
- 行号/列标可见；
- 只读，无编辑入口。

## 5. 验证

- 真实任务表日期 `2026-09-20 22:27:05` 正常显示；
- 数字/英文为系统无衬线字体，无手写回退；
- 点击单元格或表头出现蓝色选中框；
- 横向滑动时 A/B/C 与数据列同步；
- 行号 2..N 与 Grid 纵向同步；
- 系统亮色时表格为白底深字，暗色时为深底浅字；
- 网格线、表头底边、行号右边线均可见；
- 模块/进度数据验证标签颜色正常；
- 数据到第 39 行时只渲染到 41 行；
- App 中不存在 `rawfile/luckysheet`、`spreadsheet.html`、WebView 依赖。

## 6. 边界

- 合并单元格目前采用降级方案：首格保留内容，覆盖格留空；
- 复杂图表、条件格式、下拉交互不展开；
- 横向滚动由外层 Scroll 承担，Grid 负责纵向滚动；
- 表格高度完全自适应；顶部表头随页面滚动，底部 Tab 悬浮于屏幕底部。

