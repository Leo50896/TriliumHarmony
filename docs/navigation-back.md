# 系统返回行为

## 目标

全场景使用系统返回手势或物理返回键时，直接让 App 退到系统后台/主屏幕，不做应用内层级拦截。

## 实现

- 不重写 `Index.onBackPress()`；
- 不重写 `EntryAbility.onBackPressed()`；
- 不注册页面级返回状态机；
- 不添加自定义边缘热区/PanGesture；
- `SideBarContainer` 关闭自带边缘拖拽手势，避免抢占系统返回手势；
- 系统默认侧滑返回和阴影动画完整保留。

## 结果

```text
PDF 阅读中 → 系统返回 → 主屏幕
抽屉打开 → 系统返回 → 主屏幕
设置页 → 系统返回 → 主屏幕
搜索/目录面板 → 系统返回 → 主屏幕
任意场景 → 系统返回 → 主屏幕
```

抽屉仍通过左上角菜单按钮打开。

## 文件

- `pages/Index.ets`：无返回生命周期拦截
- `entryability/EntryAbility.ets`：无返回拦截
- `views/MainView.ets`：`showSideBarWithGesture(false)`，无自定义返回逻辑
