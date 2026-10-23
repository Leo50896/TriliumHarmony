# 全局搜索与阅读位置

## 1. 搜索入口

有两个入口共用同一个 `SearchView`：

1. 顶部导航栏放大镜；
2. 侧边栏顶部的伪搜索按钮（只有放大镜和“搜索全部笔记…”，不可输入）。

侧边栏点击流程：

```text
SideDrawer.onOpenGlobalSearch()
  -> MainView sets nav.openGlobalSearch = true
  -> closeDrawer()
  -> EditorView @StorageLink opens bindSheet
  -> SearchView focusController.requestFocus('globalSearchInput')
```

`SearchView` 在 `aboutToAppear` 和输入框 `onAppear` 时都会请求焦点，等待
Sheet 动画开始后执行，确保键盘直接弹出。

## 2. ETAPI 搜索

调用：

```text
GET /etapi/notes?search=<urlencoded query>
```

ETAPI 返回的是 note 元数据数组：

```json
{
  "results": [
    {
      "noteId": "...",
      "title": "...",
      "type": "text",
      "parentNoteIds": ["..."],
      "isProtected": false
    }
  ]
}
```

它**不返回路径和正文高亮**，因此 `SearchService` 在客户端补全：

### 路径

- 从 `parentNoteIds[0]` 向上走；
- 用本次搜索共享的 `Map<noteId, TriliumNote>` 缓存祖先，避免重复请求；
- 最多向上 10 层，遇到 `root` 停止；
- 拼接为 `我的知识库 / 计算机科学`，根级笔记显示 `根目录`。

### 匹配片段

- 只对 `text` / `code` 类型请求正文；
- 使用现有 `HtmlContentParser.parse()` + `plainText()` 去掉 HTML；
- 取匹配词前 36 字符、后 80 字符；
- 前后加省略号，最多显示 3 行。

## 3. 性能与限制

- 输入防抖 380ms；
- 最多返回 12 条；
- 详情补全按每批 4 条并发；
- 搜索请求用自增 sequence 丢弃过期响应；
- 由于 ETAPI 不提供路径/高亮，详情补全需要额外请求；网络较慢时会先显示“正在搜索并整理匹配片段…”；
- 搜索 401 由 `HttpService` 统一清理会话并抛 `AUTH_401`，SearchView 关闭并回到登录状态。

## 4. 选择结果

`SearchView` 只回调 noteId：

```text
SearchView.onSelect(noteId)
  -> EditorView.selectSearchResult(noteId)
  -> AppStorage.nav.selectedNoteId = noteId
  -> EditorView @Watch
  -> loadNote()
  -> showSearch = false
```

因此搜索结果和侧边栏、内部链接共用同一套选中状态。

## 5. 阅读位置

`ReadingPositionStore`：

```ts
static save(noteId, yOffset)
static get(noteId): number
static clear()
```

底层是进程级 `Map<string, number>`。不放进 AppStorage 的原因：

- scroll 事件频率高，AppStorage 会触发无意义的 UI 刷新；
- 它只是临时阅读状态，不需要跨进程持久化；
- 切换笔记时需要立即读写，Map 更直接。

### 保存

```ts
Scroll(this.scroller)
  .onDidScroll(() => {
    if (this.isRestoringScroll || this.loadedNoteId.length === 0) return;
    const offset = this.scroller.currentOffset();
    ReadingPositionStore.save(this.loadedNoteId, offset.yOffset);
  })
```

切换前还会调用 `persistScrollPosition()`，保证离开瞬间的 offset 被记录。

### 恢复

```ts
const target = ReadingPositionStore.get(noteId);
setTimeout(() => {
  this.scroller.scrollTo({ xOffset: 0, yOffset: target });
  setTimeout(() => { this.isRestoringScroll = false; }, 120);
}, 60);
```

- 60ms 等待新 block 完成布局；
- 恢复期间 `isRestoringScroll = true`，跳过布局阶段的 0 偏移；
- 120ms 后恢复保存，避免恢复动画的中间值被记录。

`SessionStore.clear()` 会调用 `ReadingPositionStore.clear()`，避免跨账号串位。

## 6. 已验证

- 搜索“算法”返回 5 条，显示标题、路径和正文片段；
- 搜索“路由器”返回 3 条；
- 点击结果关闭 Sheet 并切换 EditorView；
- 打开“路由器添加Hosts”，滚动到底部；
- 切到“算法与数据结构”后再返回；
- 截图与离开前的滚动位置一致。

## 7. 当前边界

- 阅读位置只在当前进程内有效，冷启动后从顶部开始；
- 搜索最多展示 12 条，未做分页；
- 路径依赖逐级 parent 请求，极深层级会有额外延迟；
- 保护笔记/附件/图片笔记没有正文片段，只显示路径。
