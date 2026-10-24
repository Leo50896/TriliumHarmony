# 系统返回行为

## 目标

系统返回手势/返回键优先处理应用内层级：

```text
抽屉打开 → 关闭抽屉
设置 → 返回上一个界面
开源许可 → 返回设置
笔记地图 → 返回来源界面
笔记 A → 打开笔记 B → 返回笔记 A
根界面（阅读页且无历史）→ 退出到系统
```

## 实现

- `Index` 重写 `onBackPress()`；
- `MainView` 维护两层历史：
  - `viewHistory`：editor / settings / license / notemap；
  - `noteHistory`：笔记之间的跳转；
- 只有 `nav.backAvailable === true` 时消费系统返回；
- 根界面返回 `false`，交还系统退出；
- 打开抽屉、打开设置、打开地图、点击笔记都会更新返回可用状态；
- 删除笔记时不把已删除笔记压入历史。

## 结果

```text
抽屉打开 → 系统返回 → 关闭抽屉
设置页 → 系统返回 → 阅读页
开源许可 → 系统返回 → 设置页
笔记地图 → 系统返回 → 阅读页
笔记 B → 系统返回 → 笔记 A
根阅读页 → 系统返回 → 系统桌面
```

## 文件

- `pages/Index.ets`：系统返回入口，读取 `nav.backAvailable` 并派发 `nav.backRequest`
- `views/MainView.ets`：视图历史、笔记历史与抽屉返回
- `constants/StateKeys.ets`：`nav.backRequest` / `nav.backAvailable`
