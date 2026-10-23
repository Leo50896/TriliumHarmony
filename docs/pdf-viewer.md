# PDF 阅读器

## 依赖

- `@kit.PDFKit`（HMS PDF Kit）
- `pdfService.PdfDocument`：页数、书签
- `pdfViewManager.PdfController`：加载、跳页、滚动回调

## 加载

`PdfViewer` 支持：

- `sourcePath`：离线缓存文件路径，优先使用；
- `sourceBuffer`：内存 PDF，仅在缓存写入失败时使用；
- `loadDocument(path)` / `loadDocumentFromMemory(buffer)`；
- `%PDF` 文件头校验，非 PDF 不交给 PDF Kit。

## 真机 PDF 页面

```ts
PdfView({
  controller: this.controller,
  pageLayout: pdfService.PageLayout.LAYOUT_SINGLE,
  isContinuous: true,
  showScroll: true,
  pageFit: pdfService.PageFit.FIT_WIDTH
})
```

## 标题栏

- PDF 标题和 PDF 使用同一个滚动进度平移；
- 滚动时标题栏上滑移出，PDF 同步上移填补；
- 不改变 PDF 视图高度，不重新布局原生 surface；
- 点击顶部面包屑中间整行回到开头；
- 普通笔记回到正文顶部，PDF 回到第 1 页第一行；
- 点击目录面板“回到开头”同样有效。

## 返回第一页优化

- 打开文档后预热第 1、2、3 页 HD 缓存；
- 预热按顺序执行，避免同时占用 PDF 渲染线程；
- 返回/跳页期间冻结标题栏进度，等目标页真正切换后再同步恢复，避免“标题先回、内容未动”；
- 已在第一页顶部时直接跳过跳页请求；
- 页切换完成后再延迟 120ms 预热第 1~3 页，避免抢占当前页渲染；
- 跳页期间顶部导航显示小型 LoadingProgress 作为反馈；
- 返回时立即把标题栏进度归零；
- 再调用 `goToPage(0)`，减少等待切页时的空白感。

## 目录

- 顶部导航栏目录按钮打开目录；
- 目录按需加载，打开时才创建第二个 `PdfDocument`；
- 通过 `getRootBookmarks()` 读取真实书签；
- 点击条目调用 `goToPage(pageIndex)`；
- 无书签时降级为页码目录。

## 搜索与目录 Sheet

搜索和目录共用同一个 `bindSheet`：

```ts
.bindSheet(this.showSearch || this.pdfOutlineOpen, this.ActiveSheet, ...)
```

`ActiveSheet` 根据状态渲染 `SearchSheet` 或 `PdfOutlineSheet`。不要在同一根组件上挂多个 `bindSheet`，否则 PDF 页面会出现搜索面板不显示的问题。

## 缓存

- `<cacheDir>/pdf/<encoded noteId>.pdf`；
- 最多 5 个文件 / 50MB；
- 按修改时间 LRU；
- 命中缓存时直接 `loadDocument(path)`，跳过网络。

## 加密 PDF

- `PARSE_ERROR_PASSWORD` 或异常包含 `password/encrypted`；
- 显示“该 PDF 已加密，暂不支持预览”；
- `finally` 确保 loading 关闭。

## 模拟器

- 当前模拟器没有 HMS PDF 服务实现；
- `productModel=emulator` 时不挂载 `PdfView`，避免 native 闪退；
- 显示“模拟器不支持 PDF Kit，请使用真机预览”。
