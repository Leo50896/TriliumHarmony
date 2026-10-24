import {
  ContentBlock,
  ContentBlockKind,
  ImageData
} from '../utils/HtmlContentParser';
import { TriliumCodec } from '../utils/codec/TriliumCodec';
import { TriliumImage } from './TriliumImage';

export interface ComplexBlockEditorParams {
  block: ContentBlock;
  onSave: (nextBlock: ContentBlock) => void;
  onCancel: () => void;
}

/**
 * Full-screen editor host for structured blocks.
 *
 * Phase one: images use a property panel; tables and callouts use a raw HTML
 * editor as the safe fallback. The host never saves directly: it returns a new
 * ContentBlock to EditorView, keeping the codec/save pipeline in one place.
 */
@Component
export struct ComplexBlockEditorHost {
  @Prop block: ContentBlock = new ContentBlock(ContentBlockKind.PARAGRAPH);
  onSave: (nextBlock: ContentBlock) => void = () => {};
  onCancel: () => void = () => {};

  @State private rawMode: boolean = false;
  @State private rawHtml: string = '';
  @State private src: string = '';
  @State private alt: string = '';
  @State private titleText: string = '';
  @State private href: string = '';
  @State private caption: string = '';
  @State private widthPercent: number = 0;
  @State private widthPx: number = 0;
  @State private heightPx: number = 0;

  aboutToAppear(): void {
    this.rawHtml = this.block.raw;
    this.rawMode = this.block.kind !== ContentBlockKind.IMAGE;
    if (this.block.image !== null) {
      const image: ImageData = this.block.image;
      this.src = image.src;
      this.alt = image.alt;
      this.titleText = image.title;
      this.href = image.href;
      this.caption = image.figureCaption;
      this.widthPercent = image.widthPercent;
      this.widthPx = image.width;
      this.heightPx = image.height;
    }
  }

  private title(): string {
    if (this.block.kind === ContentBlockKind.IMAGE) {
      return '编辑图片';
    }
    if (this.block.kind === ContentBlockKind.TABLE) {
      return '编辑表格';
    }
    if (this.block.kind === ContentBlockKind.CALLOUT) {
      return '编辑 Callout';
    }
    return '编辑块';
  }

  private close(): void {
    this.onCancel();
  }

  private saveRaw(): void {
    if (this.rawHtml.trim().length === 0) {
      return;
    }
    const parsed: ContentBlock = TriliumCodec.parseBlock(this.rawHtml, 'html');
    parsed.id = this.block.id;
    parsed.raw = this.rawHtml;
    parsed.dirty = true;
    parsed.serializeMode = 'raw';
    this.onSave(parsed);
  }

  private saveImage(): void {
    const image: ImageData = new ImageData(this.src, this.alt, this.widthPercent,
      this.titleText, this.widthPx, this.heightPx, this.href, this.caption, this.block.raw);
    const next: ContentBlock = new ContentBlock(this.block.kind, this.block.text,
      this.block.level, this.block.codeLines, this.block.language, this.block.segments,
      this.block.listItems, this.block.table, image, this.block.listMarkers,
      this.block.callout, this.block.include, this.block.listLevels, this.block.indent,
      this.block.quoteBlocks, this.block.id, this.block.raw, this.block.source);
    next.attrs = this.block.attrs;
    next.children = this.block.children;
    next.dirty = true;
    next.serializeMode = 'model';
    this.onSave(next);
  }

  private save(): void {
    if (this.rawMode || this.block.kind !== ContentBlockKind.IMAGE) {
      this.saveRaw();
    } else {
      this.saveImage();
    }
  }

  @Builder
  private ImagePanel() {
    Column({ space: 12 }) {
      Column() {
        TriliumImage({
          src: this.src,
          alt: this.alt,
          widthPercent: this.widthPercent
        })
      }
      .width('100%')
      .constraintSize({ maxHeight: 260 })
      .backgroundColor($r('app.color.bg_secondary'))
      .borderRadius(8)
      .padding(8)

      this.Field('图片地址', this.src, 'https://…', (value: string) => {
        this.src = value;
      })
      this.Field('替代文本', this.alt, '图片描述', (value: string) => {
        this.alt = value;
      })
      this.Field('标题', this.titleText, 'tooltip title', (value: string) => {
        this.titleText = value;
      })
      this.Field('链接', this.href, '点击图片跳转的地址', (value: string) => {
        this.href = value;
      })
      this.Field('图注', this.caption, 'figure / figcaption', (value: string) => {
        this.caption = value;
      })

      Row({ space: 12 }) {
        Text('宽度 %')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
        TextInput({ text: this.widthPercent > 0 ? `${this.widthPercent}` : '' })
          .type(InputType.Number)
          .layoutWeight(1)
          .height(36)
          .fontSize(13)
          .onChange((value: string) => {
            const parsed: number = Number(value);
            this.widthPercent = isNaN(parsed) ? 0 : parsed;
          })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private Field(label: string, value: string, placeholder: string,
    onChange: (value: string) => void) {
    Column({ space: 5 }) {
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
      TextInput({ text: value, placeholder: placeholder })
        .width('100%')
        .height(38)
        .fontSize(13)
        .onChange(onChange)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private RawPanel() {
    Column({ space: 8 }) {
      Text(this.block.kind === ContentBlockKind.TABLE ?
        '表格暂用原始 HTML 编辑，保存后会重新解析为表格块。' :
        'Callout 暂用原始 HTML 编辑，保存后会重新解析。')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
      TextArea({ text: this.rawHtml, placeholder: '原始 HTML' })
        .width('100%')
        .layoutWeight(1)
        .fontSize(12)
        .fontFamily('monospace')
        .backgroundColor($r('app.color.bg_secondary'))
        .borderRadius(8)
        .border({ width: 1, color: $r('app.color.border') })
        .padding(10)
        .onChange((value: string) => {
          this.rawHtml = value;
        })
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Row() {
        Text(this.title())
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text('取消')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .padding(8)
          .onClick(() => {
            this.close();
          })
        Text('保存')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary'))
          .padding(8)
          .onClick(() => {
            this.save();
          })
      }
      .width('100%')
      .height(52)

      if (this.block.kind === ContentBlockKind.IMAGE && !this.rawMode) {
        Scroll() {
          this.ImagePanel()
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)

        Text('高级：编辑原始 HTML')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .padding({ top: 8, bottom: 8 })
          .onClick(() => {
            this.rawMode = true;
          })
      } else {
        this.RawPanel()
        if (this.block.kind === ContentBlockKind.IMAGE) {
          Text('返回属性面板')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .padding({ top: 8, bottom: 8 })
            .onClick(() => {
              this.rawMode = false;
            })
        }
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 16 })
    .backgroundColor($r('app.color.bg_primary'))
  }
}
