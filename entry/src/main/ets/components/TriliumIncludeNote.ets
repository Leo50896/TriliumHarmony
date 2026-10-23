import { AppIcon } from './AppIcon';
import { CodeBlock } from './CodeBlock';
import { TriliumCallout } from './TriliumCallout';
import { TriliumTable } from './TriliumTable';
import { AuthSession } from '../models/AuthModels';
import { EtapiService } from '../services/EtapiService';
import { SessionStore } from '../services/SessionStore';
import {
  ContentBlock,
  ContentBlockKind,
  HtmlContentParser,
  InlineSegment
} from '../utils/HtmlContentParser';

/**
 * Trilium `.include-note` block.
 *
 * Desktop renders the included note inline. We fetch both metadata and content,
 * then render the included blocks with the same native readers used by the
 * current note. Large includes are capped and scrolled inside the block.
 */
@Component
export struct TriliumIncludeNote {
  @Prop noteId: string = '';
  @Prop boxSize: string = 'medium';
  @Prop block: string = '';
  onOpen: (noteId: string) => void = () => {};

  @State private title: string = '';
  @State private blocks: ContentBlock[] = [];
  @State private isLoading: boolean = true;

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    const session: AuthSession | null = SessionStore.currentSession();
    if (session === null || this.noteId.length === 0) {
      this.isLoading = false;
      return;
    }
    try {
      const note = await EtapiService.getNote(session, this.noteId);
      this.title = note.title;
      const html: string = await EtapiService.getNoteContent(session, this.noteId);
      this.blocks = HtmlContentParser.parse(html, note.type, note.mime);
    } catch (error) {
      this.title = '';
    } finally {
      this.isLoading = false;
    }
  }

  private displayTitle(): string {
    if (this.title.length > 0) {
      return this.title;
    }
    return this.isLoading ? '正在读取引用笔记…' : `引用笔记 ${this.noteId}`;
  }

  @Builder
  private IncludedBlock(block: ContentBlock) {
    if (block.kind === ContentBlockKind.CALLOUT) {
      if (block.callout !== null) {
        TriliumCallout({
          callout: block.callout,
          onLink: () => {}
        })
      }
    } else if (block.kind === ContentBlockKind.TABLE) {
      if (block.table !== null) {
        TriliumTable({
          table: block.table,
          onLink: () => {}
        })
      }
    } else if (block.kind === ContentBlockKind.CODE) {
      CodeBlock({
        fileName: this.displayTitle(),
        language: block.language.length > 0 ? block.language : 'CODE',
        sourceLines: block.codeLines
      })
    } else if (block.kind === ContentBlockKind.LIST) {
      Column({ space: 5 }) {
        ForEach(block.listItems, (item: InlineSegment[], index: number) => {
          Row({ space: 7 }) {
            Text(index < block.listMarkers.length ? block.listMarkers[index] : '•')
              .width(18)
              .textAlign(TextAlign.Center)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
            Text(HtmlContentParser.segmentsText(item))
              .fontSize(15)
              .lineHeight(24)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }, (item: InlineSegment[], index: number) => `${index}-${index}`)
      }
      .width('100%')
    } else if (block.kind === ContentBlockKind.IMAGE) {
      // Included images are rendered by nested callouts/tables.
    } else {
      Text(HtmlContentParser.segmentsText(block.segments))
        .fontSize(block.kind === ContentBlockKind.HEADING ? 19 : 15.5)
        .lineHeight(block.kind === ContentBlockKind.HEADING ? 28 : 25)
        .fontWeight(block.kind === ContentBlockKind.HEADING ? FontWeight.Medium : FontWeight.Normal)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding({ top: 2, bottom: 2 })
    }
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        AppIcon({
          icon: $r('app.media.ic_doc'),
          iconSize: 16,
          tint: $r('app.color.primary')
        })
        Text(this.displayTitle())
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('包含笔记')
          .fontSize(10.5)
          .fontColor($r('app.color.text_tertiary'))
        Text('›')
          .fontSize(18)
          .fontColor($r('app.color.text_tertiary'))
          .onClick(() => {
            if (this.noteId.length > 0) {
              this.onOpen(this.noteId);
            }
          })
      }
      .width('100%')

      if (this.blocks.length === 0 && this.isLoading) {
        Text('正在加载引用内容…')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
      } else {
        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.blocks, (block: ContentBlock, index: number) => {
              this.IncludedBlock(block)
            }, (block: ContentBlock, index: number) => `${index}-${block.kind}`)
          }
          .width('100%')
        }
        .width('100%')
        .constraintSize({ maxHeight: 560 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .padding(12)
    .margin({ top: 8, bottom: 8 })
    .backgroundColor($r('app.color.bg_secondary'))
    .border({ width: 1, color: $r('app.color.border') })
    .borderRadius(12)
    .onClick(() => {
      if (this.noteId.length > 0) {
        this.onOpen(this.noteId);
      }
    })
  }
}
