# Trilium 上游参考范围

为避免把 Web/Electron 技术栈带进鸿蒙工程，本项目的上游仓库只作为 **数据结构和 API 协议** 参考，UI 与数据库实现一律不使用。

## 上游快照

```text
目录:   trilium/
来源:   https://github.com/zadam/trilium.git
分支:   main
提交:   f864dc86231f4f2ea9255a0ba2f977496a884e59
方式:   shallow clone（--depth 1 --single-branch）
文件数: 6087
```

> `zadam/trilium` 当前会跳转到 TriliumNext/Trilium 的最新 monorepo，因此目录结构是新版 `apps/` + `packages/`，不是旧版 `src/` 布局。

## 明确边界

**允许参考**

- OpenAPI 规范中的请求/响应字段、状态码、认证方式；
- 实体说明中的字段语义和实体关系；
- 路由路径、分页/搜索参数等协议层信息。

**禁止照搬**

- `apps/client/**`：React/Preact、jQuery、Electron、CSS、widget 等前端代码；
- `packages/trilium-core/**` 中的 SQLite schema、migration、SQL、数据库访问实现；
- `apps/server/**` 中的后端业务实现、Express 路由实现、登录实现；
- 任何 Node.js/Electron 运行时依赖。

**UI 规则**

本项目所有界面必须继续使用 **ArkTS + ArkUI** 编写：`@Component`、`@State`、`ForEach`、`Navigation`、`SideBarContainer`、`Stack` 等；不引入 React、Preact、Electron 或 WebView 作为 UI 层。

## 已选定的参考文件

| 文件 | 用途 | 是否已读 |
| --- | --- | --- |
| `apps/server/src/assets/etapi.openapi.yaml` | ETAPI 对外 API 契约，首选协议来源 | 仅读登录段与路由索引 |
| `apps/server/internal.openapi.yaml` | 内部 `/api/*` 契约，含登录/TOTP | 仅读登录、TOTP 路由索引 |
| `apps/server/src/routes/api/login.ts` | `/api/login/token` 的状态码、`token` 字段和 `factor` | 仅读该文件 |
| `apps/server/src/services/auth.ts` | 密码/TOTP 校验顺序与 `factor` 返回 | 仅读登录相关函数 |
| `apps/web-clipper/entrypoints/options/main.tsx` | 浏览器扩展调用 `/api/login/token` 的请求契约 | 仅读 `requestToken()`，不复制 UI |
| `docs/Developer Guide/Developer Guide/Concepts/Entities.md` | 六个核心实体关系 | 全文（109 行） |
| `docs/Developer Guide/Developer Guide/Architecture/APIs.md` | Internal API / ETAPI / WebSocket 边界 | 全文（72 行） |
| `docs/User Guide/User Guide/Installation & Setup/Server Installation/Multi-factor authentication with TOTP.md` | TOTP 用户流程 | 仅检索摘要 |
| `.claude/skills/developing-web-clipper/SKILL.md` | `/api/login/token` 版本兼容注意事项 | 仅读相关段落 |

其余文件未做逐文件阅读。

## 核心数据模型

Trilium 的数据模型以六个实体为核心：

- **Note**：标题、类型、内容、时间戳、保护状态；
- **Branch**：Note 的父子关系，支持一个 Note 被多个父节点引用（clone）；
- **Attribute**：Note 的键值元数据，分为 label 和 relation 两种；
- **Revision**：Note 内容的历史版本；
- **Attachment**：Note 的附件，含 owner、role、MIME type；
- **Blob**：实际内容/附件二进制，供 Note、Revision、Attachment 引用。

对鸿蒙客户端的启示：

- 树结构不能只建模成 `Note.children`，需要 `Branch` 来表达多父节点；
- 标签和关系应统一建模为 `Attribute`，不要只做扁平 tags；
- 笔记正文与附件内容应按需拉取，不要塞进列表 DTO；
- `Note.type` 决定编辑器/渲染器类型（text、code、file、image、canvas、mermaid 等）。

## API 协议（当前已确认）

### ETAPI（推荐优先适配）

Base path：`/etapi`

- `POST /etapi/auth/login`
  - `application/json`
  - body：`{ "password": "..." }`
  - 201：`{ "authToken": "..." }`
  - 后续请求使用 `Authorization: <authToken>` 头
- `POST /etapi/auth/logout`
- `GET /etapi/app-info`
- `POST/GET /etapi/notes`、`/etapi/notes/{noteId}`、`/etapi/notes/{noteId}/content`
- `POST/GET /etapi/branches`、`/etapi/attributes`、`/etapi/attachments`
- `GET /etapi/notes/{noteId}/revisions`、`/etapi/notes/{noteId}/attachments`

OpenAPI 是机器可读的权威来源：

```text
trilium/apps/server/src/assets/etapi.openapi.yaml
```

### 内部 Web API（登录与 TOTP）

Base path：`/api`

- `GET /bootstrap`
  - 无需凭据
  - `login.totpEnabled` 表示服务器是否开启 TOTP
  - 客户端用它在提交密码前决定是否进入第二步
- `POST /api/login`
  - `application/x-www-form-urlencoded`
  - 字段：`password`，以及启用 2FA 时的 `totpToken`
  - 200：设置 `trilium.sid` 会话 Cookie
  - 401：密码或 TOTP/恢复码错误
- `POST /api/login/token`
  - `application/json`
  - 字段：`password`、`totpToken`、可选 `tokenName`
  - 200/201：`{ "token": "..." }`（旧文档写 `authToken`，客户端两者兼容）
- TOTP 管理：
  - `GET /api/totp/status`
  - `GET /api/totp/generate`
  - `POST /api/totp/verify`
  - `POST /api/totp/enable`
  - `POST /api/totp/reset`
  - `POST /api/totp_recovery/verify`

需要注意：Trilium 的真实登录模型是 **密码和 TOTP 在同一次 `/api/login/token` 请求中提交**，不存在自造的 `/api/auth/2fa/verify` challenge 流程。两步 UI 仍然保留，但第一步只检测 `totpEnabled`，第二步才把 `password + totpToken` 一起提交。

此外，旧版/部分部署的 `/api/login/token` 在 401 时只返回纯文本 `Incorrect credential`，不返回 `factor`；因此不能依赖 401 的 `factor` 判断 2FA，必须读取 `/bootstrap`。

## 当前鸿蒙工程已落地

[AuthService](../entry/src/main/ets/services/AuthService.ets) 默认使用真实模式：

```text
GET  /bootstrap                    → login.totpEnabled
POST /api/login/token              → { token }
Authorization: <token>             → ETAPI
```

- `MockConfig.USE_MOCK` 默认为 `false`；
- 登录页默认服务器为真实 Trilium 地址；
- 账号密码不写进源码；
- TOTP 由用户在第二步手动输入；
- ETAPI Token 存入 preferences（生产环境应使用 HUKS 保护）。

目录同步已落地在 [EtapiService](../entry/src/main/ets/services/EtapiService.ets)：

```text
GET /etapi/notes/root
GET /etapi/notes/{noteId}
Authorization: <token>
```

- `SideDrawer` 先加载 root 的直接子节点，再在展开文件夹时懒加载其子节点；
- 每批最多 6 个并发 note 请求；
- `Refresh` 容器负责下拉刷新，刷新后恢复已展开节点；
- 搜索目前只在已加载节点中过滤。

阅读与编辑已落地在 [EditorView](../entry/src/main/ets/views/EditorView.ets)：

```text
GET /etapi/notes/{noteId}/content
PATCH /etapi/notes/{noteId}          { "title": "..." }
PUT /etapi/notes/{noteId}/content    text/plain
```

- 文本笔记的 HTML 由 `utils/HtmlContentParser.ets` 解析为 ArkUI 标题/段落/引用/列表/代码块；
- 代码笔记整篇渲染为 `CodeBlock`；
- 标签来自 `attributes`，过滤内部 label；
- 编辑模式保留原始 HTML/源码，保存时写回 ETAPI；
- 图片/文件/受保护笔记只显示占位说明。

尚未完成：

1. 服务端全库搜索（`GET /etapi/notes?search=...`）；
2. 新建/重命名/删除笔记的完整流程（标题与正文保存已接入）；
3. 图片、附件、TODO checkbox 的真实交互；
4. 本地缓存与增量同步。

上游 JSON 已映射到 `models/TriliumModels.ets`，UI 不直接依赖上游字段命名；ETAPI 的 `Authorization` 头与错误码语义保持不变。SQLite、React/Preact 和 Electron 代码没有进入鸿蒙工程。

## 参考时的工作规则

- 先读 OpenAPI，不先读实现；
- 只打开与当前任务相关的单个文件，不批量扫描 `apps/client` 或 SQL 目录；
- 不复制上游 TypeScript/TSX/CSS/SQL 代码；
- 不引入上游依赖；
- ArkUI 组件结构、状态管理和路由保持本项目现有实现。
