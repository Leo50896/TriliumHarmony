# Trilium Include Note 卡片

## 1. 上游格式

Trilium 的引用笔记（include note）不是 `include-note` 自定义元素，而是带类名的
HTML 容器。上游 `apps/client/src/widgets/type_widgets/text/utils.ts` 和
`packages/trilium-core/src/share/content_renderer.ts` 使用：

```html
<section class="include-note" data-note-id="noteId" data-box-size="medium"></section>
```

块引用可能是：

```html
<figure class="include-note" data-note-id="noteId"
        data-block="blockId" data-box-size="medium"></figure>
```

附件嵌入使用 `data-attachment-id`，不是笔记引用。

另外：

- `a.reference-link` 是行内笔记链接，继续沿用 `InlineTextView` + 内部链接路由；
- 代码块在存储中是 `<pre><code>`，现有 `parse` 已提取为 `CODE_BLOCK`，无需新增
  `code-block` 包装类。

## 2. 解析

`HtmlContentParser.ets`：

```ts
class IncludeNoteData {
  noteId: string;
  boxSize: string;
  block: string;
}
```

新增：

```ts
ContentBlockKind.INCLUDE
ContentBlock.include
```

解析步骤：

1. 在 code/table/image 处理前匹配 `<section|figure class="... include-note ...">`；
2. 读取 `data-note-id`；
3. 读取 `data-box-size`、`data-block`；
4. 替换为 `@@INCLUDE_n@@` 占位符；
5. `parseMarkedText` 消费占位符，生成 `INCLUDE` block。

没有 `data-note-id` 的附件嵌入返回空字符串，不生成笔记卡片。

## 3. 卡片组件

`TriliumIncludeNote.ets`：

- 通过 ETAPI `GET /etapi/notes/{noteId}` 异步读取标题；
- 标题返回前显示“正在读取引用笔记…”；
- 失败时回退为 `引用笔记 <noteId>`；
- 卡片显示：
  - “引用笔记”
  - 目标笔记标题
  - `包含笔记 · medium` 或 `块引用 · blockId`
- 点击卡片调用 `onOpen(noteId)`。

## 4. 路由

当前 App 没有独立 NoteDetail 页面，主界面是：

```text
SideBarContainer
  ├── SideDrawer
  └── EditorView（唯一阅读/编辑 surface）
```

所以没有使用 `router.pushUrl`，而是复用已有内部路由：

```text
onOpen(noteId)
  -> EditorView.openLink("#root/<noteId>")
  -> TriliumLinkRouter.open()
  -> AppStorage.nav.selectedNoteId = noteId
  -> EditorView @Watch 重新加载
```

这与 `router.pushUrl` 的用户可见效果一致：点击卡片进入目标笔记；同时不会压入
重复页面，也不会破坏抽屉/阅读位置/搜索等现有状态。

如果后续引入真正的多页面 Navigation，再把 `onOpen` 改成 `router.pushUrl` 即可，
解析器和卡片组件不需要重写。

## 5. 验证

临时测试笔记：

```html
<section class="include-note" data-note-id="d6CdfZEgEP83"
         data-box-size="medium"></section>
```

结果：

- 卡片显示“引用笔记 / 算法与数据结构 / 包含笔记 · medium”；
- 点击卡片切换到“算法与数据结构”；
- 卡片之后的普通段落仍正常渲染；
- 临时测试笔记已通过 ETAPI 删除。

## 6. 边界

- `include-note` 只渲染卡片，不内联展开完整正文；
- 标题需要一次 ETAPI 请求；离线时回退为 noteId；
- 嵌套 include、非笔记 attachment embed 还未做完整展开；
- 目标笔记不存在时仍显示卡片，点击后由 EditorView 显示加载错误。
