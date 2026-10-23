import { MermaidGraph, MermaidNode, MermaidParser } from '../utils/MermaidParser';

/**
 * Minimal native Mermaid renderer for the common `flowchart TB` form.
 *
 * Trilium's desktop editor shows the source and the rendered chart side by
 * side. On a phone we render the chart, with the source available in the code
 * viewer when the graph cannot be interpreted.
 */
@Component
export struct MermaidFlowchart {
  @Prop sourceLines: string[] = [];

  private graph(): MermaidGraph {
    return MermaidParser.parse(this.sourceLines);
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        Text('MERMAID')
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_tertiary'))
          .letterSpacing(0.6)
          .backgroundColor($r('app.color.bg_secondary'))
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(4)
        Blank()
        Text('流程图')
          .fontSize(10.5)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })

      Column({ space: 0 }) {
        ForEach(this.graph().nodes, (node: MermaidNode, index: number) => {
          Column({ space: 0 }) {
            Text(node.label)
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .textAlign(TextAlign.Center)
              .width('100%')
              .padding({ top: 8, bottom: 8 })
              .border({ width: 1, color: $r('app.color.text_secondary') })
              .borderRadius(2)
            if (index < this.graph().nodes.length - 1) {
              Column({ space: 0 }) {
                Row()
                  .width(1)
                  .height(16)
                  .backgroundColor($r('app.color.text_secondary'))
                Text('▼')
                  .fontSize(9)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        }, (node: MermaidNode, index: number) => `${index}-${node.id}`)
      }
      .width('100%')
      .padding({ left: 22, right: 22, top: 14, bottom: 18 })

      Divider()
        .color($r('app.color.border'))
        .strokeWidth(1)

      Row({ space: 8 }) {
        Text('源码')
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_tertiary'))
          .letterSpacing(0.4)
        Blank()
        Text('MERMAID')
          .fontSize(9.5)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 4 })

      Scroll() {
        Column({ space: 2 }) {
          ForEach(this.sourceLines, (line: string, index: number) => {
            Row({ space: 10 }) {
              Text(`${index + 1}`)
                .fontSize(10)
                .fontFamily('monospace')
                .fontColor($r('app.color.text_tertiary'))
                .width(20)
                .textAlign(TextAlign.End)
              Text(line)
                .fontSize(11.5)
                .fontFamily('monospace')
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }, (line: string, index: number) => `${index}-${line}`)
        }
        .width('100%')
        .padding({ left: 4, right: 12, top: 6, bottom: 10 })
      }
      .width('100%')
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .constraintSize({ maxHeight: 220 })
    }
    .width('100%')
    .margin({ top: 8, bottom: 8 })
    .backgroundColor($r('app.color.bg_primary'))
    .border({ width: 1, color: $r('app.color.border') })
    .borderRadius(6)
    .clip(true)
  }
}
