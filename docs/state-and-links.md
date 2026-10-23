# 全局状态与内部链接设计

本文记录 SideDrawer、EditorView、图片组件之间的会话/导航同步方式，以及
Trilium 内部链接的拦截路径。

## 1. 结论

使用 **AppStorage 作为跨组件唯一响应式状态源**，`SessionStore` 作为唯一写入口。
`@Provide/@Consume` 只适合 MainView 内部的局部 UI 状态，不用于跨兄弟组件和深层
Reader 组件同步会话。

原因：

- SideDrawer 和 EditorView 是 `SideBarContainer` 下的兄弟组件；
- TriliumImage 位于 EditorView -> Callout/Table 的深层树；
- ImagePreview 在 Modal 中；
- 逐层 props 或 `@Consume` 会把 Token 传递散落到每个组件。

## 2. AppStorage Key

定义在 `constants/StateKeys.ets`：

| Key | 类型 | 写入方 | 读取方 |
| --- | --- | --- | --- |
| `auth.token` | string | SessionStore | SideDrawer、EditorView、TriliumImage、ImagePreview |
| `auth.serverUrl` | string | SessionStore | 同上 |
| `auth.refreshToken` | string | SessionStore | TokenStore/后续续期 |
| `auth.expiresAt` | number | SessionStore | Session 恢复 |
| `auth.username` | string | SessionStore | 设置页/调试 |
| `auth.loggedIn` | boolean | SessionStore | Index 登录门禁 |
| `nav.selectedNoteId` | string | SideDrawer、TriliumLinkRouter | EditorView、SideDrawer 高亮 |
| `nav.selectedNoteTitle` | string | SideDrawer、LinkRouter | 面包屑/占位（可选） |

AppStorage 只放字符串、布尔值和数字，**不放 PixelMap、笔记正文或 HTML**。

## 3. 生命周期

### 冷启动

```text
Index.aboutToAppear
  -> SessionStore.installDefaults()
  -> SessionStore.initialize(context)
       -> TokenStore.getValidSession(context)
       -> SessionStore.applySession(session)
            -> auth.token/serverUrl/loggedIn 写入 AppStorage
  -> phase = 2
  -> MainView
       -> SideDrawer  @StorageProp token -> syncTree()
       -> EditorView  @StorageLink selectedNoteId
```

### 登录成功

```text
AuthService -> AuthResult.session
  -> LoginView.completeLogin
       -> SessionStore.save(context, session)
            -> TokenStore.saveSession
            -> AppStorage.setOrCreate(auth.*)
  -> onAuthenticated() -> phase = 2
```

如果 Previewer 没有 AbilityContext，则调用 `SessionStore.applySession(session)`，
保留当前进程内会话。

### 退出/401

```text
HttpService detects 401
  -> await SessionStore.clear()
       -> TokenStore.clearSession
       -> auth.* = ''/false
       -> nav.selectedNoteId = ''
  -> throw Error('AUTH_401')
       -> Index @StorageLink('auth.loggedIn') 变为 false
       -> phase = 1 (LoginView)
```

## 4. SessionStore API

```ts
SessionStore.installDefaults()
SessionStore.initialize(context): Promise<AuthSession | null>
SessionStore.save(context, session): Promise<void>
SessionStore.applySession(session): void
SessionStore.clear(): Promise<void>
SessionStore.currentSession(): AuthSession | null
SessionStore.token(): string
SessionStore.serverUrl(): string
SessionStore.isLoggedIn(): boolean
```

所有会话写入集中在 `SessionStore`，业务组件不直接调用
`AppStorage.setOrCreate('auth.token', ...)`。

## 5. 组件订阅方式

### SideDrawer

```ts
@StorageProp('auth.token') @Watch('onTokenChanged') token: string = '';
@StorageLink('nav.selectedNoteId') selectedNoteId: string = '';
```

点击笔记：

```ts
this.selectedNoteId = node.noteId;
AppStorage.setOrCreate(StateKeys.SELECTED_NOTE_TITLE, node.title);
this.onOpenNote(node.noteId, node.title);
this.onCloseDrawer();
```

`onOpenNote` 只用于关闭抽屉，不再传递 `selectedNoteId` 数据。

### EditorView

```ts
@StorageLink('nav.selectedNoteId') @Watch('onNoteIdChanged') noteId: string = '';
@StorageProp('auth.token') @Watch('onAuthChanged') authToken: string = '';
```

- SideDrawer 写入 Id；
- EditorView 的 `@Watch` 调用 `loadNote()`；
- `MainView` 不再保存 `selectedNoteId`；
- Token 变化时重置本地 `session` 并重新加载当前笔记。

### TriliumImage / ImagePreview

```ts
@StorageProp('auth.token') @Watch('onAuthChanged') accessToken: string = '';
@StorageProp('auth.serverUrl') @Watch('onAuthChanged') serverUrl: string = '';
```

- EditorView、TriliumTable、TriliumCallout 不再传 `serverUrl/accessToken`；
- 表格单元格图片、Callout 图片、正文图片共用同一份会话；
- Preview 在 Modal 内重新加载图片，避免 PixelMap 跨 Modal 失效。

## 6. HttpService 401 收口

`HttpService.request()` 是 ETAPI 与图片请求的统一入口：

```ts
const response = await request.request(url, options);
if (response.responseCode === 401) {
  if (clearOn401) {
    await SessionStore.clear();
  }
  throw new Error('AUTH_401');
}
```

覆盖：

- `EtapiService` 的 notes/content/title PATCH；
- `TriliumImage` 的附件/图片 content；
- `ImagePreview` 的 Modal 内图片加载。

不覆盖：

- `/api/login/token` 的 401。它表示密码或 TOTP 错误，不是会话过期；
  误清已有会话会让“密码输错一次就被登出”；
- `/bootstrap` 等未鉴权探测请求。

上层只处理 `AUTH_401` 交互，不再重复写清除逻辑。

## 7. 内部链接路由

`TriliumLinkRouter.ets` 支持：

```text
#root/<noteId>
#<noteId>
/root/<noteId>
trilium://root/<noteId>
```

点击流程：

```text
InlineTextView.onLink
  -> EditorView.openLink
       -> TriliumLinkRouter.open(href)
            -> AppStorage.nav.selectedNoteId = noteId
            -> EditorView @Watch
            -> loadNote()
```

因此正文、Callout、表格中的链接都走同一条链路，不会打开新的 ArkUI 页面，
也不会依赖 Navigation 路由栈。

外部链接仍由 `EditorView.openLink` 显示提示，不冒充内部路由。

## 8. 已验证

- 冷启动读取 preferences 中的 Token，SideDrawer 直接同步真实目录；
- SideDrawer 点击“车辆工程”后 EditorView 自动切换并渲染；
- 临时笔记中的 `<a href="#root/0Eoz9Z1pVi9d">` 点击后切换到“工作空间”；
- 同一篇临时笔记中的图片由 AppStorage Token 成功加载；
- 临时测试笔记通过 ETAPI 删除，未修改用户笔记。

## 9. 取舍

- AppStorage 不是加密存储；Token 的安全边界仍在 preferences，生产环境建议
  后续用 HUKS 保护 refresh token；
- `selectedNoteId` 只保存 Id，不保存正文/滚动位置；
- Token 变更时会重新加载当前笔记，避免显示旧会话数据；
- 401 只负责清会话，不做自动 refresh；续期策略仍待后续实现。
