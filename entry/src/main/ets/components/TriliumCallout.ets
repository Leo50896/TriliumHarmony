import { CodeBlock } from './CodeBlock';
import { InlineTextView } from './InlineTextView';
import { TriliumImage } from './TriliumImage';
import { TriliumTable } from './TriliumTable';
import { AttributeVisuals } from '../utils/AttributeVisuals';
import {
  CalloutData,
  ContentBlock,
  ContentBlockKind,
  HtmlContentParser,
  InlineSegment
} from '../utils/HtmlContentParser';

/**
 * Trilium admonition (callout) card.
 *
 * Trilium serializes these as:
 *   <aside class="admonition note|tip|important|caution|warning"> ... </aside>
 *
 * The accent colors and 15% tinted background match admonitions.css. Nested
 * blocks are rendered with the same native readers used by the main note.
 */
@Component
export struct TriliumCallout {
  @Prop callout: CalloutData = new CalloutData('note', 'ℹ️', '#69C7FF', []);
  onLink: (href: string) => void = () => {};

  private tint(): ResourceColor {
    const hex: string = this.callout.accentColor.replace('#', '');
    if (hex.length === 6) {
      return `#26${hex}`;
    }
    if (hex.length === 8) {
      return `#26${hex.substring(2)}`;
    }
    return $r('app.color.callout_tint');
  }

  private listItemSegments(item: InlineSegment[]): InlineSegment[] {
    if (item.length === 0) {
      return item;
    }
    const text: string = HtmlContentParser.segmentsText(item);
    if (!text.startsWith('☐ ') && !text.startsWith('☑ ')) {
      return item;
    }
    const copy: InlineSegment[] = item.slice();
    const first: InlineSegment = copy[0];
    copy[0] = new InlineSegment(first.text.substring(2).replace(/^\s+/, ''),
      first.bold, first.italic, first.code, first.href, first.color, first.backgroundColor);
    return copy;
  }

  private listMarker(block: ContentBlock, index: number): string {
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
    if (block.kind === ContentBlockKind.HEADING) {
      InlineTextView({
        segments: block.segments,
        fontSize: block.level === 1 ? 24 : (block.level === 2 ? 21 : 18),
        lineHeight: block.level === 1 ? 32 : 28,
        color: $r('app.color.text_primary'),
        weight: FontWeight.Medium,
        onLink: this.onLink
      })
    } else if (block.kind === ContentBlockKind.LIST) {
      Column({ space: 5 }) {
        ForEach(block.listItems, (item: InlineSegment[], index: number) => {
          Row({ space: 6 }) {
            if (HtmlContentParser.segmentsText(item).startsWith('☐ ') ||
              HtmlContentParser.segmentsText(item).startsWith('☑ ')) {
              Text(HtmlContentParser.segmentsText(item).substring(0, 1))
                .width(20)
                .textAlign(TextAlign.Center)
                .fontSize(15.5)
                .lineHeight(25)
                .fontColor(HtmlContentParser.segmentsText(item).startsWith('☑') ?
                  $r('app.color.success') : $r('app.color.text_secondary'))
            } else {
              Text(this.listMarker(block, index))
                .width(20)
                .textAlign(TextAlign.Center)
                .fontSize(15.5)
                .lineHeight(25)
                .fontColor($r('app.color.text_secondary'))
            }
            Column() {
              InlineTextView({
                segments: this.listItemSegments(item),
                fontSize: 15.5,
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
        }, (item: InlineSegment[], index: number) => `${index}-${HtmlContentParser.segmentsText(item)}`)
      }
      .width('100%')
    } else if (block.kind === ContentBlockKind.QUOTE) {
      InlineTextView({
        segments: block.segments,
        fontSize: 15,
        lineHeight: 24,
        color: $r('app.color.text_secondary'),
        italic: true,
        onLink: this.onLink
      })
    } else if (block.kind === ContentBlockKind.CODE) {
      CodeBlock({
        fileName: 'snippet',
        language: block.language.length > 0 ? block.language : 'CODE',
        sourceLines: block.codeLines
      })
    } else if (block.kind === ContentBlockKind.TABLE) {
      if (block.table !== null) {
        TriliumTable({
          table: block.table,
          onLink: this.onLink
        })
      }
    } else if (block.kind === ContentBlockKind.IMAGE) {
      if (block.image !== null) {
        TriliumImage({
          src: block.image.src,
          alt: block.image.alt,
          widthPercent: block.image.widthPercent
        })
      }
    } else if (block.kind === ContentBlockKind.CALLOUT) {
      if (block.callout !== null) {
        TriliumCallout({
          callout: block.callout,
          onLink: this.onLink
        })
      }
    } else {
      Column() {
        InlineTextView({
          segments: block.segments,
          fontSize: 15.5,
          lineHeight: 25,
          color: $r('app.color.text_primary'),
          onLink: this.onLink
        })
      }
      .width('100%')
      .padding({ left: block.indent })
    }
  }

  build() {
    Row({ space: 9 }) {
      Text(AttributeVisuals.glyph(this.callout.icon))
        .fontFamily('boxicons')
        .fontSize(17)
        .fontColor(this.callout.accentColor)
        .width(24)
        .textAlign(TextAlign.Center)
        .alignSelf(ItemAlign.Start)
        .margin({ top: 1 })

      Column({ space: 7 }) {
        ForEach(this.callout.blocks, (block: ContentBlock, index: number) => {
          this.BlockView(block)
        }, (block: ContentBlock, index: number) => `${block.kind}-${index}`)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 12, right: 13, top: 11, bottom: 12 })
    .backgroundColor(this.tint())
    .border({ width: { left: 3, top: 1, right: 1, bottom: 1 },
      color: this.callout.accentColor })
    .borderRadius(9)
    .margin({ top: 2, bottom: 2 })
  }
}
