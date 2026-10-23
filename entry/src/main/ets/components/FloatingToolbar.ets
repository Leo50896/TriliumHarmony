import { AppIcon } from './AppIcon';

class EditorTool {
  label: string;
  action: string;

  constructor(label: string, action: string) {
    this.label = label;
    this.action = action;
  }
}

/**
 * Floating editor toolbar. The tool strip scrolls horizontally while the
 * primary save button stays pinned on the right.
 */
@Component
export struct FloatingToolbar {
  onAction: (action: string) => void = () => {};
  onDone: () => void = () => {};

  private tools: EditorTool[] = [
    new EditorTool('B', 'bold'),
    new EditorTool('I', 'italic'),
    new EditorTool('H1', 'h1'),
    new EditorTool('H2', 'h2'),
    new EditorTool('¶', 'paragraph'),
    new EditorTool('•', 'bullet'),
    new EditorTool('1.', 'ordered'),
    new EditorTool('☐', 'checklist'),
    new EditorTool('</>', 'code'),
    new EditorTool('🖼', 'image'),
    new EditorTool('❝', 'quote'),
    new EditorTool('ⓘ', 'callout'),
    new EditorTool('📄', 'include'),
    new EditorTool('▦', 'table'),
    new EditorTool('ab¹', 'math'),
    new EditorTool('+', 'insert'),
    new EditorTool('≡', 'align'),
    new EditorTool('⇤', 'outdent'),
    new EditorTool('⇥', 'indent'),
    new EditorTool('◫', 'columns'),
    new EditorTool('M↓', 'export'),
    new EditorTool('Ω', 'symbol'),
    new EditorTool('☺', 'emoji'),
    new EditorTool('✎', 'pen')
  ];

  @Builder
  private ToolButton(tool: EditorTool) {
    Text(tool.label)
      .fontSize(15)
      .fontColor($r('app.color.text_secondary'))
      .width(40)
      .height(40)
      .textAlign(TextAlign.Center)
      .borderRadius(10)
      .backgroundColor($r('app.color.bg_input'))
      .onClick(() => {
        this.onAction(tool.action);
      })
  }

  build() {
    Row({ space: 8 }) {
      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.tools, (tool: EditorTool) => {
            this.ToolButton(tool)
          }, (tool: EditorTool) => tool.action)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .layoutWeight(1)

      Stack({ alignContent: Alignment.Center }) {
        Row()
          .width(46)
          .height(46)
          .borderRadius(23)
          .backgroundColor($r('app.color.primary'))
          .shadow({
            radius: 14,
            color: $r('app.color.logo_shadow'),
            offsetX: 0,
            offsetY: 4
          })
        AppIcon({
          icon: $r('app.media.ic_check'),
          iconSize: 21,
          tint: $r('app.color.text_on_primary')
        })
      }
      .width(52)
      .height(52)
      .onClick(this.onDone)
    }
    .width('100%')
    .height(58)
    .padding({ left: 8, right: 6, top: 5, bottom: 5 })
    .backgroundColor($r('app.color.bg_elevated'))
    .borderRadius(20)
    .border({ width: 1, color: $r('app.color.border') })
    .shadow({
      radius: 24,
      color: $r('app.color.shadow'),
      offsetX: 0,
      offsetY: 8
    })
  }
}
