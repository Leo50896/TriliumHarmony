import { CodeBlock } from './CodeBlock';
import { InlineTextView } from './InlineTextView';
import { TriliumCallout } from './TriliumCallout';
import { TriliumTable } from './TriliumTable';
import {
  CollapsibleData,
  ContentBlock,
  ContentBlockKind,
  HtmlContentParser,
  InlineSegment
} from '../utils/HtmlContentParser';

/**
 * Trilium `<details class="trilium-collapsible">` renderer.
 *
 * The header is a muted title bar with a disclosure chevron, and nested lists
 * keep their per-level bullet markers and indentation, matching the editor.
 */
@Component
export struct TriliumCollapsible {
  @Prop collapsible: CollapsibleData = new CollapsibleData('', []);
  @State private expanded: boolean = true;
  onLink: (href: string) => void = () => {};

  private marker(block: ContentBlock, index: number): string {
    const level: number = index < block.listLevels.length ? block.listLevels[index] : 0;
    const marker: string = index < block.listMarkers.length ? block.listMarkers[index] : '•';
    if (marker === '•' || marker === '-' || marker === '*' || marker.length === 0) {
      const bullets: string[] = ['•', '◦', '▪', '•'];
      return bullets[Math.min(3, Math.max(0, level))];
    }
    if (/^\d+\.$/.test(marker) && level === 4) {
      return 'a.';
    }
    if (/^\d+\.$/.test(marker) && level >= 5) {
      return 'i.';
    }
    return marker;
  }

  @Builder
  private BlockView(block: ContentBlock) {
    if (block.kind === ContentBlockKind.LIST) {
      Column({ space: 5 }) {
        ForEach(block.listItems, (item: InlineSegment[], index: number) => {
          Row({ space: 6 }) {
            Text(HtmlContentParser.segmentsText(item).startsWith('☐ ') ||
              HtmlContentParser.segmentsText(item).startsWith('☑ ') ?
              HtmlContentParser.segmentsText(item).substring(0, 1) : this.marker(block, index))
              .width(20)
              .textAlign(TextAlign.Center)
              .fontSize(15)
              .lineHeight(25)
              .fontColor(HtmlContentParser.segmentsText(item).startsWith('☑') ?
                $r('app.color.success') : $r('app.color.text_secondary'))
            Column() {
              InlineTextView({
                segments: item,
                fontSize: 15,
                lineHeight: 25,
                color: HtmlContentParser.segmentsText(item).startsWith('☑') ?
                  $r('app.color.text_tertiary') : $r('app.color.text_primary'),
                onLink: this.onLink
              })
            }
            .layoutWeight(1)
          }
          .width('100%')
          .padding({
            left: (index < block.listLevels.length ? block.listLevels[index] : 0) * 20
          })
          .alignItems(VerticalAlign.Top)
        }, (item: InlineSegment[], index: number) =>
          `${index}-${HtmlContentParser.segmentsText(item)}`)
      }
      .width('100%')
    } else if (block.kind === ContentBlockKind.TABLE) {
      if (block.table !== null) {
        TriliumTable({ table: block.table, onLink: this.onLink })
      }
    } else if (block.kind === ContentBlockKind.CALLOUT) {
      if (block.callout !== null) {
        TriliumCallout({ callout: block.callout, onLink: this.onLink })
      }
    } else if (block.kind === ContentBlockKind.CODE) {
      CodeBlock({
        fileName: 'collapsible',
        language: block.language.length > 0 ? block.language : 'CODE',
        sourceLines: block.codeLines
      })
    } else {
      InlineTextView({
        segments: block.segments,
        fontSize: 15,
        lineHeight: 25,
        color: $r('app.color.text_primary'),
        onLink: this.onLink
      })
    }
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        Text(this.expanded ? '⌄' : '›')
          .fontSize(16)
          .fontColor($r('app.color.text_secondary'))
          .width(18)
          .textAlign(TextAlign.Center)
        Text(this.collapsible.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor($r('app.color.bg_secondary'))
      .onClick(() => {
        this.expanded = !this.expanded;
      })

      if (this.expanded) {
        Divider()
          .color($r('app.color.border'))
          .strokeWidth(1)
        Column({ space: 6 }) {
          ForEach(this.collapsible.blocks, (block: ContentBlock, index: number) => {
            this.BlockView(block)
          }, (block: ContentBlock, index: number) => `${index}-${block.kind}`)
        }
        .width('100%')
        .padding({ left: 16, right: 12, top: 10, bottom: 12 })
      }
    }
    .width('100%')
    .margin({ top: 8, bottom: 8 })
    .backgroundColor($r('app.color.bg_primary'))
    .border({ width: 1, color: $r('app.color.border') })
    .borderRadius(5)
    .clip(true)
  }
}
