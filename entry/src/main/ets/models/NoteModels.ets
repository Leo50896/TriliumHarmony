export class NoteTag {
  label: string;

  constructor(label: string) {
    this.label = label;
  }
}

export class TodoItem {
  id: string;
  text: string;
  done: boolean;

  constructor(id: string, text: string, done: boolean) {
    this.id = id;
    this.text = text;
    this.done = done;
  }
}

export class NoteDocument {
  id: string;
  title: string;
  tags: NoteTag[];
  updatedLabel: string;
  wordCount: number;
  synced: boolean;
  paragraphs: string[];
  quote: string;
  quoteOwner: string;
  codeFileName: string;
  codeLanguage: string;
  codeLines: string[];
  todos: TodoItem[];

  constructor(id: string, title: string, tags: NoteTag[], updatedLabel: string, wordCount: number, synced: boolean,
    paragraphs: string[], quote: string, quoteOwner: string, codeFileName: string, codeLanguage: string,
    codeLines: string[], todos: TodoItem[]) {
    this.id = id;
    this.title = title;
    this.tags = tags;
    this.updatedLabel = updatedLabel;
    this.wordCount = wordCount;
    this.synced = synced;
    this.paragraphs = paragraphs;
    this.quote = quote;
    this.quoteOwner = quoteOwner;
    this.codeFileName = codeFileName;
    this.codeLanguage = codeLanguage;
    this.codeLines = codeLines;
    this.todos = todos;
  }
}

export const ARKUI_NOTE: NoteDocument = new NoteDocument(
  'note-arkui-state',
  'ArkUI 状态管理',
  [new NoteTag('#鸿蒙'), new NoteTag('#前端')],
  '今天 10:32',
  1847,
  true,
  [
    'ArkUI 的状态管理以装饰器为核心：@State 驱动当前组件刷新，@Prop / @Link 建立父子同步，@Provide / @Consume 实现跨层级注入。',
    '状态应当尽量靠近真正消费它的组件。共享范围越小，刷新边界就越清晰，页面在大数据量下也越稳定。'
  ],
  '官方建议：优先使用最小粒度的状态定义，避免不必要的整树刷新。',
  'ArkUI 官方文档',
  'index.ets',
  'ARKTS',
  [
    '@Entry',
    '@Component',
    'struct Index {',
    '  @State count: number = 0',
    '',
    '  build() {',
    '    Column() {',
    '      Text(`count = ${this.count}`)',
    '        .fontSize(20)',
    '      Button(\'Add\')',
    '        .onClick(() => this.count++)',
    '    }',
    '  }',
    '}'
  ],
  [
    new TodoItem('todo-1', '装饰器选型对比表', true),
    new TodoItem('todo-2', '@Watch 侦听器实验', false),
    new TodoItem('todo-3', '补充一个跨层级注入示例', false)
  ]
);
