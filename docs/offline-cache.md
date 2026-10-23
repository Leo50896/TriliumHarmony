# 本地离线缓存

## 1. 目标

正文请求失败时（断网、超时、服务不可达），如果这篇笔记最近成功打开过，
就用本地缓存的 HTML 继续阅读，并明确标记“离线缓存”。

缓存不替代服务端数据；联网成功后仍以 ETAPI 返回内容为准。

## 2. 存储

使用 HarmonyOS `relationalStore`：

```text
数据库：trilium_offline.db
表：note_cache
主键：(account_key, note_id)
```

字段：

| 字段 | 用途 |
| --- | --- |
| `note_id` | 笔记 ID |
| `account_key` | `serverUrl|username`，避免跨账号串数据 |
| `title` | 标题 |
| `type` / `mime` | 渲染类型 |
| `date_modified` | 修改时间 |
| `tags` | `visibleLabels()` 的 JSON |
| `is_protected` | 保护状态 |
| `content` | 原始 HTML / 源码 |
| `cached_at` | 写入时间 |
| `last_viewed` | 最近阅读时间，用于淘汰 |

限制：

- 缓存 `text` / `code` / `spreadsheet`；spreadsheet 存原始 Univer JSON，离线仍由原生 `NativeSheetView` 渲染；
- 保护笔记、图片、附件不缓存；
- 单条内容超过 1.5MB 不缓存（RDB 单字段建议低于 2MB）；
- 每个账号保留最近 **20** 篇；
- 图片本身不缓存，离线时图片会显示占位/失败状态。

## 3. 写入

`EditorView` 在网络加载成功后异步写入：

```ts
this.cacheNote(note, content);
```

`cacheNote` 不阻塞渲染，失败只忽略，不影响阅读。写入后按
`last_viewed DESC` 淘汰超出 20 篇的旧记录。

## 4. 读取回退

```text
loadNote()
  -> ETAPI getNote + getNoteContent
       ├── 成功：正常渲染 + 异步缓存
       └── 失败（非 401）：
             -> NoteCacheStore.get(accountKey, noteId)
                  ├── 命中：渲染缓存内容 + isOffline = true
                  └── 未命中：显示“网络不可用，且没有本地缓存”
```

401 不读缓存，因为登录状态失效时不应继续展示本地内容。

## 5. 离线 UI

- 标题下状态从“已同步”变为 `离线缓存 · HH:mm`；
- 增加黄色“离线阅读”提示卡，说明图片与编辑不可用；
- 离线时隐藏“编辑”按钮；
- `beginEdit` / `saveNote` / `saveRichEdit` 都有离线只读保护；
- SideDrawer 的 `/etapi/notes` 请求失败且不是 401 时，抽屉顶部显示黄色
  “网络不可用” Warning，副标题提示“当前显示最近缓存的笔记，联网后下拉刷新”；
- 同一抽屉下方显示最近 8 篇缓存笔记（`NoteCacheStore.recent`），
  点击可直接进入离线阅读；
- 在线同步成功后 `isNetworkOffline = false`，Warning 自动消失。

## 6. 测试

由于模拟器 `eth0` 无法通过普通 shell 关闭，使用了一个临时构建强制
`loadNote()` 抛出网络错误，验证缓存回退；测试后已移除该临时代码。

验证结果：

- 算法与数据结构 → 离线缓存命中；
- 标题、标签、正文、checklist 正常渲染；spreadsheet 可离线渲染；
- 显示 `离线缓存 · 02:20`；
- 编辑按钮隐藏；
- 读取内容和缓存时间正确。

## 7. 当前边界

- 只缓存正文，不缓存图片附件；
- 侧边栏离线入口只列出最近 8 篇，在线目录仍以 ETAPI 为准；
- 阅读位置 Map 仍只保存在进程内，冷启动后从顶部开始；
- 缓存是明文 SQLite 数据，生产环境如需更强保护可结合 HUKS/加密数据库。
