export enum DrawerItemType {
  FOLDER = 0,
  NOTE = 1
}

export class DrawerItem {
  id: string;
  label: string;
  level: number;
  type: DrawerItemType;
  expanded: boolean;
  selected: boolean;
  hasChildren: boolean;

  constructor(id: string, label: string, level: number, type: DrawerItemType, expanded: boolean,
    selected: boolean, hasChildren: boolean) {
    this.id = id;
    this.label = label;
    this.level = level;
    this.type = type;
    this.expanded = expanded;
    this.selected = selected;
    this.hasChildren = hasChildren;
  }
}

export class RecentItem {
  id: string;
  title: string;

  constructor(id: string, title: string) {
    this.id = id;
    this.title = title;
  }
}

export function createDrawerItems(): DrawerItem[] {
  return [
    new DrawerItem('knowledge', '我的知识库', 0, DrawerItemType.FOLDER, true, false, true),
    new DrawerItem('coding', '编程', 1, DrawerItemType.FOLDER, true, false, true),
    new DrawerItem('arkui', 'ArkUI 状态管理', 2, DrawerItemType.NOTE, true, true, true),
    new DrawerItem('untitled', '未命名笔记', 3, DrawerItemType.NOTE, false, false, false),
    new DrawerItem('python', 'Python 脚本集', 2, DrawerItemType.NOTE, false, false, false),
    new DrawerItem('frontend', '前端工程化', 2, DrawerItemType.NOTE, false, false, false),
    new DrawerItem('algorithms', '算法与数据结构', 2, DrawerItemType.NOTE, false, false, false),
    new DrawerItem('books', '读书笔记', 0, DrawerItemType.FOLDER, false, false, true),
    new DrawerItem('journal', '日记 2026', 0, DrawerItemType.FOLDER, false, false, true),
    new DrawerItem('favorites', '收藏夹', 0, DrawerItemType.FOLDER, false, false, true),
    new DrawerItem('readlater', '稍后读', 0, DrawerItemType.FOLDER, false, false, true)
  ];
}

export const RECENT_ITEMS: RecentItem[] = [
  new RecentItem('meeting-q4', '周会纪要 · Q4'),
  new RecentItem('dunhuang', '敦煌旅行清单')
];

export class SettingsNavItem {
  id: string;
  icon: Resource;
  title: string;
  value: string;
  showChevron: boolean;

  constructor(id: string, icon: Resource, title: string, value: string, showChevron: boolean) {
    this.id = id;
    this.icon = icon;
    this.title = title;
    this.value = value;
    this.showChevron = showChevron;
  }
}

export const ACCOUNT_SETTINGS: SettingsNavItem[] = [
  new SettingsNavItem('server', $r('app.media.ic_server'), '服务器状态', '已连接', false),
  new SettingsNavItem('sync', $r('app.media.ic_clock'), '同步频率', '自动', true),
  new SettingsNavItem('account', $r('app.media.ic_user'), '账户信息', '', true)
];

export const APPEARANCE_SETTINGS: SettingsNavItem[] = [
  new SettingsNavItem('theme', $r('app.media.ic_theme'), '主题', '暗黑', true),
  new SettingsNavItem('code-theme', $r('app.media.ic_code'), '代码高亮主题', 'Monokai', true)
];
