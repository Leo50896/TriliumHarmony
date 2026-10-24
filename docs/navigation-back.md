# 系统返回行为

## 目标

系统返回手势/返回键优先处理应用内层级：

```text
抽屉打开 → 关闭抽屉
设置 → 返回阅读页
开源许可 → 返回设置
笔记地图 → 返回来源界面
阅读页根界面 → 退出到系统
再次启动 → 回到上次笔记与阅读位置
```

## 实现

- `Index` 重写 `onBackPress()`；
- `MainView` 维护 `viewHistory`：editor / settings / license / notemap；
- 阅读页不保留笔记返回栈，返回时直接交给系统退出；
- 只有 `nav.backAvailable === true` 时消费系统返回；
- `ReadingPositionStore` 将最后笔记与各笔记 scrollY 持久化到 preferences；
- 打开笔记、滚动阅读都会更新持久化数据；
- 冷启动时先恢复 `lastNoteId`，`EditorView` 再恢复该笔记的滚动位置。

## 结果

```text
抽屉打开 → 系统返回 → 关闭抽屉
设置页 → 系统返回 → 阅读页
开源许可 → 系统返回 → 设置页
笔记地图 → 系统返回 → 阅读页
阅读页 → 系统返回 → 系统桌面
重新打开 App → 上次笔记 + 上次阅读位置
```

## 文件

- `pages/Index.ets`：系统返回入口，恢复最后阅读的笔记
- `views/MainView.ets`：视图历史与抽屉返回；不再记录笔记返回栈
- `services/ReadingPositionStore.ets`：笔记与滚动位置持久化
- `constants/StateKeys.ets`：`nav.backRequest` / `nav.backAvailable`
