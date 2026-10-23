# Trilium 富文本排版值提取（CKEditor）

本文只提取 Trilium / CKEditor 内容区的排版数值，不复刻 React/CSS 代码。

## 1. 实际源码位置

仓库中没有 `apps/client/src/styles/`，实际目录是：

```text
apps/client/src/stylesheets/                    # 客户端主题与内容样式
apps/client/src/widgets/type_widgets/text/      # ReadOnlyText.css 等文本组件样式
apps/edit-docs/demo/style.css                   # CKEditor 5 表格/图片基础样式副本
packages/ckeditor5/src/theme/                   # 自定义 CKEditor 插件样式
```

关键文件：

| 文件 | 用途 |
| --- | --- |
| `apps/client/src/stylesheets/style.css` | inline code、链接、表格表头覆盖、图片 caption |
| `apps/client/src/stylesheets/theme-next/notes/text.css` | 引用、表格 caption、链接、标题字重 |
| `apps/client/src/stylesheets/theme-next/forms.css` | `.use-tn-links` 链接字重/圆角/悬浮背景 |
| `apps/client/src/stylesheets/theme-next-dark.css` | 暗色主题颜色变量 |
| `apps/client/src/stylesheets/theme-next-light.css` | 亮色主题颜色变量 |
| `apps/client/src/widgets/type_widgets/text/ReadOnlyText.css` | 只读正文图片 `max-width: 100%` |
| `apps/edit-docs/demo/style.css` | CKEditor 5 表格边框/单元格 padding/图片居中基础规则 |

## 2. 单位基准

Trilium 正文：

```css
.ck-content {
    --ck-content-font-size: 1.1em;
    --ck-content-line-height: var(--bs-body-line-height);
}
```

浏览器根字号按 `16px` 计算：

```text
正文 = 1.1 × 16 = 17.6 CSS px
```

当前鸿蒙模拟器：

```text
侧边栏 304vp = 截图 912px
density = 912 / 304 = 3.0
1vp = 3 物理 px
```

因此本项目的换算关系：

```text
1 CSS px ≈ 1vp ≈ 3 物理 px（当前 3.0 密度）
```

> ArkUI 的 `.padding(7)` 是 7vp；如果写成 `.padding('7px')`，只有 7 物理 px，会小三倍。
> 下面统一使用 vp，px 列仅作说明。

`em` 是相对当前元素字号：

- inline code 的 `0.8em` 相对于 17.6px 正文 → 14.08px；
- inline code 的 `padding: 0.1em 0.35em` 相对于它自己的 14.08px；
- 表格单元格的 `0.4em` 相对于 17.6px 正文。

## 3. 行内代码（inline code）

来源：

- `apps/client/src/stylesheets/style.css:859-867`
- 颜色变量：`theme-next-dark.css:302-304`、`theme-next-light.css:301-303`
- 字体：`style.css:289-293`、`theme-next/base.css:51`

| 属性 | CSS 值 | CSS px | ArkUI vp | 物理 px @3x |
| --- | --- | --- | --- | --- |
| 字体 | `"JetBrains Mono", monospace` | — | `fontFamily('JetBrains Mono')` | — |
| 字号 | `0.8em` | 14.08 | **14vp** | 42px |
| 垂直 padding | `0.1em` | 1.41 | **1.5vp**（取 1.4） | 4.2px |
| 水平 padding | `0.35em` | 4.93 | **5vp** | 15px |
| 圆角 | `5px` | 5 | **5vp** | 15px |
| 文字颜色 | `inherit` | — | 继承正文色 | — |
| 边框 | 无（变量存在但规则未使用） | — | 无 | — |
| 换行 | `overflow-wrap: break-word` | — | `WordBreak.BREAK_ALL` | — |

背景色：

| 主题 | CSS 值 | ArkUI 颜色 |
| --- | --- | --- |
| 暗色（Next Dark） | `rgba(255,255,255,0.08)` | `#14FFFFFF` |
| 亮色（Next Light） | `rgba(0,0,0,0.05)` | `#0D000000` |
| 通用回退 | `rgba(128,128,128,0.18)` | `#2E808080` |

当前 App 是暗色主题，使用 `#14FFFFFF`。

## 4. 链接（link）

来源：

- 基础链接：`style.css:179-185`
- hover 下划线：`style.css:954-956`
- `.use-tn-links` 字重/圆角/悬浮背景：`theme-next/forms.css:534-565`
- 颜色：`theme-next-dark.css:88-90`、`theme-next-light.css:88-90`

| 属性 | 暗色 | 亮色 | ArkUI |
| --- | --- | --- | --- |
| 颜色 | `#95C3D9` | `#0076AF` | `fontColor('#95C3D9')` |
| 字重 | `500` | `500` | `FontWeight.Medium` |
| 默认下划线 | 无 | 无 | `TextDecorationType.None` |
| hover 下划线 | `underline`（实线，自动粗细） | 同左 | `TextDecorationType.Underline` |
| hover 背景（14%） | `#75C2E324` | `#3C7FA017` | `#2475C2E3` / `#173C7FA0` |
| 圆角 | `4px` | `4px` | **4vp** |
| 下划线粗细 | auto，约 1px | 同左 | **1vp** |

说明：

- Trilium 普通链接默认**没有下划线**，hover 才出现；
- 引用笔记链接（`reference-link`）默认也不加下划线，hover 时只给内部 `span` 加；
- 当前 ArkUI 实现在触屏上没有可靠 hover，因此链接改为常驻下划线，保证可点击性；点击/悬停仍有按压背景反馈。

> 当前 SDK：DevEco Studio 使用 **API 26 / HarmonyOS 7.0.0**，`compatibleSdkVersion` 为 5.0.0(12)。`ContainerSpan` 与 `textBackgroundStyle` 从 API 11 起可用，因此当前版本支持行内代码背景，不需要拆成多个 `Text`。

## 5. 表格（table）

来源：

- CKEditor 5 表格基础规则：`apps/edit-docs/demo/style.css:600-623`
- Trilium 表头背景覆盖：`style.css:940-942`
- 单元格文字/垂直对齐：`style.css:262-267`
- 表格 caption：`theme-next/notes/text.css:863-865`
- 表头背景变量：`theme-next-dark.css:28`、`theme-next-light.css:28`

| 属性 | CSS 值 | ArkUI vp | 物理 px @3x |
| --- | --- | --- | --- |
| 外边框 | `1px double #B3B3B3` | **1vp**（建议用 1vp solid；要可见 double 用 3vp） | 3px |
| 单元格边框 | `1px solid #BFBFBF` | **1vp** | 3px |
| 单元格 padding | `0.4em` | **7vp** | 21px |
| 单元格最小宽度 | `2em` | **35vp** | 105px |
| 表格外边距 | `0.9em auto` | **16vp auto** | 48px |
| 表头背景（暗） | `var(--accented-background-color)` = `#555555` | `#555555` | — |
| 表头背景（亮） | `#F5F5F5` | `#F5F5F5` | — |
| 表头字重 | `bold` | `FontWeight.Bold` | — |
| 表头对齐 | `text-align:start` | `TextAlign.Start` | — |
| 单元格垂直对齐 | `middle` | `VerticalAlign.Center` | — |
| 单元格文字（暗/亮） | `#CCCCCC` / `#000000` | 对应主题色 | — |
| 表格宽度 | 屏幕下 `100%` | `width('100%')` | — |
| 布局 | `border-collapse:collapse` | 用 0 间距 Grid/Row 模拟 | — |
| 表头内段落 margin | 首尾 `0` | 单元格内 Text 不额外加 margin | — |

注意：

- CKEditor 默认表头背景是 `#0000000d`，但 Trilium 用 `style.css:940` 覆盖成 `--accented-background-color`，所以运行时暗色是 `#555555`，不是 5% 黑。
- `1px double` 在 1px 宽度下通常看不出双线；ArkUI 没有原生 double border，建议 1vp solid，或 3vp 双线自绘。
- 表格 caption：`padding: .6em` ≈ **8vp**，`font-size: .75em` ≈ **13vp**，背景同样用 `#555555` / `#F5F5F5`。

## 6. 图片（image）

来源：

- CKEditor 图片容器/居中：`apps/edit-docs/demo/style.css:215-255`
- 只读正文图片：`apps/client/src/widgets/type_widgets/text/ReadOnlyText.css:10-13` 和 `:49-52`
- 图片 caption：`style.css:944-947`

| 属性 | CSS 值 | ArkUI vp |
| --- | --- | --- |
| 最大宽度 | `max-width: 100%` | `constraintSize({ maxWidth: '100%' })` |
| 高度 | `height: auto` | 保持宽高比 |
| 容器最小宽度 | `min-width: 50px` | **50vp** |
| 容器外边距 | `margin: .9em auto` | **16vp auto** |
| 居中方式 | 容器 `text-align:center`；`img` `margin:0 auto; display:block` | 外层 `Row().justifyContent(FlexAlign.Center)` |
| 图片显示 | `display:block` | `Image` 默认块级布局 |
| 缩放图 | `.image_resized` `max-width:100%`，`img width:100%` | `width('100%')` + `objectFit(ImageFit.Contain)` |
| 只读图片 | `max-width:100%; height:auto` | 同上 |

CSS 同时写了 `min-width:100%` 和 `max-width:100%`，实际由 CKEditor 的 `figure.image` 尺寸约束；原生实现建议只强制 `maxWidth: 100%`，避免小图被放大。

## 7. 数值速查

| CSS | vp | 物理 px @3x |
| --- | --- | --- |
| 1px | 1vp | 3px |
| 1.4px | 1.4vp | 4.2px |
| 5px | 5vp | 15px |
| 7px | 7vp | 21px |
| 8px | 8vp | 24px |
| 14px | 14vp | 42px |
| 16px | 16vp | 48px |
| 35px | 35vp | 105px |
| 50px | 50vp | 150px |

## 8. ArkUI 映射注意

1. **inline code**：ArkUI `Span` 支持 `textBackgroundStyle({ color, radius })`，但不支持 padding。要实现 1.5/5vp 内边距，需要在文本两侧加 NBSP，或使用自定义行内布局；纯 `Text` 方案只能做到背景+圆角。
2. **link**：用 `Span` 设置 `fontColor`、`decoration`、`onClick`；hover 态在触屏上可用按压态替代。
3. **table**：ArkUI 没有原生 table，建议 `Grid` + 自绘边框；1vp 边框，单元格 7vp padding，表头 `#555555`。
4. **image**：`Row` 居中 + `Image.constraintSize({ maxWidth: '100%' })` + `ImageFit.Contain`；不要写 `width('100%')` 除非确实要拉伸。
5. 当前 [HtmlContentParser](../entry/src/main/ets/utils/HtmlContentParser.ets) 已保留 inline code、链接、粗体/斜体、表格和图片节点，并按下面的方式渲染。

## 9. 当前实现状态

- 行内代码：`InlineTextView.ets` 使用 `ContainerSpan` + 前后透明 NBSP 实现背景/圆角/内边距，代码 Span 使用 `fontFamily('monospace')`；
- 粗体/斜体：`Span` 的 `fontWeight(600)` 和 `fontStyle(Italic)`；
- 链接：`Span` 默认常驻下划线，支持 `onClick`/`onHover`，不支持 `onTouch`；外部 `http(s)/mailto` 通过 `UIAbilityContext.openLink` 交给系统浏览器，失败回退 `startAbility` VIEW Want；内部 `#root/<id>` 由 `TriliumLinkRouter` 原地切换；
- 所有行内片段由同一个父级 `Text` 承载，内部只用 `Span` / `ContainerSpan`，保证自动换行；
- 图片：`TriliumImage.ets` 把 `api/attachments/<id>/...` 映射为 `/etapi/attachments/<id>/content`，把 `api/images/<noteId>/...` 映射为 `/etapi/notes/<noteId>/content`，带 `Authorization` 请求后转 `PixelMap`；
  - 点击图片通过 `bindContentCover` 打开全屏 `ImagePreview`；
  - 预览支持双指捏合 0.5x–3x、双击 2.5x/还原、放大后单指平移、单指点击关闭；
  - 预览内重新用同一套 ETAPI 映射加载图片，避免 PixelMap 跨 Modal 失效；
- 表格：`TriliumTable.ets` 用 Row/Column 模拟，外框 1vp `#B3B3B3`，单元格右/下 1vp `#BFBFBF`，padding 7vp，表头 `#555555`；外层使用 10vp 圆角和卡片背景；
- 有序列表：解析器识别 `<ol start="n">`，序号使用 24vp 固定宽度 Text，内容折行后与正文左边缘对齐；
- 表格单元格内嵌图片：`TableCell.images`，由 `TriliumImage` 在单元格 Column 中正常布局，不裁剪；
- `rowspan` 降级：内容在后续行重复渲染，使用 `continuation` 弱化背景；不足列用透明 placeholder 补齐；
- Callout：解析 `<aside class="admonition <type>">`，`TriliumCallout.ets` 渲染图标、15% 色调背景、1vp 彩色边框、9vp 圆角和内部嵌套块；类型颜色取自 `admonitions.css`：
  - note `#69C7FF`、tip `#40C025`、important `#9839F7`、caution `#FF2E2E`、warning `#E2AA03`；
- 行内颜色：`<span style="color:hsl(...)">` / `background-color`，解析器把 hsl/rgb 转成 ArkUI 可用的 hex，并交给 Span；
- 内部标记：统一过滤 `@@HEADING_2@@`、`@@LIST@@` 等残留占位符，避免原始标记进入正文；
- 轻编辑：`RichEditor` 仅用于只含段落/标题/粗斜体的文本，B/I/H1/H2 工具栏；复杂内容回退源码；
- 已用临时笔记验证 inline code、粗体、斜体、链接、2 列表格、单元格附件图片、Callout 和 RichEditor 保存；临时笔记已删除。

### Span 的 onTouch 限制

ArkUI `Span` 明确只支持 `onClick` / `onHover`，不支持 `onTouch`。因此链接无法在按下瞬间拿到 TouchEvent；当前做法是：

- 鼠标/触控板：`onHover` 切换下划线和背景；
- 触屏：`onClick` 触发后保持 180ms 的按压反馈。

如果必须严格使用 `onTouch`，需要把链接拆成独立 `Text` 放进 `Flex`，会牺牲行内混排和自然换行，不建议为当前阅读页采用。
