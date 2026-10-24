import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import {
  ContentBlock,
  ContentBlockKind,
  CalloutData,
  ImageData,
  InlineSegment,
  TableCell,
  TableData,
  TableRow
} from '../utils/HtmlContentParser';
import { TriliumCodec } from '../utils/codec/TriliumCodec';
import { TriliumImage } from './TriliumImage';

class EditableCell {
  text: string;
  rowSpan: number;
  colSpan: number;
  header: boolean;
  continuation: boolean;
  source: TableCell | null;

  constructor(text: string, rowSpan: number = 1, colSpan: number = 1,
    header: boolean = false, continuation: boolean = false,
    source: TableCell | null = null) {
    this.text = text;
    this.rowSpan = rowSpan;
    this.colSpan = colSpan;
    this.header = header;
    this.continuation = continuation;
    this.source = source;
  }
}

class EditableRow {
  cells: EditableCell[];

  constructor(cells: EditableCell[]) {
    this.cells = cells;
  }
}

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
  @Prop startInRawMode: boolean = false;
  onSave: (nextBlock: ContentBlock) => void = () => {};
  onAutoSave: (nextBlock: ContentBlock) => void = () => {};
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
  @State private tableRows: EditableRow[] = [];
  @State private calloutType: string = 'note';
  @State private calloutTitle: string = '';
  @State private calloutChildren: ContentBlock[] = [];
  @State private calloutChildTick: number = 0;
  @State private keyboardInset: number = 0;
  private tableScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.rawHtml = this.block.raw;
    this.rawMode = this.startInRawMode;
    this.bindKeyboard();
    if (this.block.callout !== null) {
      this.calloutType = this.block.callout.type;
      this.calloutTitle = this.block.callout.title;
      this.calloutChildren = this.block.callout.blocks.slice();
    }
    if (this.block.table !== null) {
      for (let r = 0; r < this.block.table.rows.length; r++) {
        const row: TableRow = this.block.table.rows[r];
        const cells: EditableCell[] = [];
        for (let c = 0; c < row.cells.length; c++) {
          const cell: TableCell = row.cells[c];
          cells.push(new EditableCell(cell.text(), cell.rowspan, cell.colspan,
            cell.header, cell.continuation, cell));
        }
        this.tableRows.push(new EditableRow(cells));
      }
    }
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

  private bindKeyboard(): void {
    const context: common.UIAbilityContext | null = this.hostContext();
    if (context === null) {
      return;
    }
    window.getLastWindow(context).then((mainWindow: window.Window) => {
      mainWindow.on('keyboardHeightChange', (height: number) => {
        this.keyboardInset = height > 0 ? px2vp(height) : 0;
      });
    }).catch(() => {
      // Keyboard avoidance is best-effort.
    });
  }

  private hostContext(): common.UIAbilityContext | null {
    const context: common.Context | undefined = this.getUIContext().getHostContext();
    return context === undefined ? null : context as common.UIAbilityContext;
  }

  private scrollTableTo(rowIndex: number): void {
    setTimeout(() => {
      try {
        this.tableScroller.scrollTo({
          xOffset: 0,
          yOffset: Math.max(0, rowIndex * 63 - 90)
        });
      } catch (error) {
        // Scroller may not be attached yet.
      }
    }, 80);
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

  private canChangeTableShape(): boolean {
    for (let r = 0; r < this.tableRows.length; r++) {
      for (let c = 0; c < this.tableRows[r].cells.length; c++) {
        const cell: EditableCell = this.tableRows[r].cells[c];
        if (cell.rowSpan > 1 || cell.colSpan > 1 || cell.continuation) {
          return false;
        }
      }
    }
    return true;
  }

  private addTableRow(): void {
    let columns: number = 1;
    for (let r = 0; r < this.tableRows.length; r++) {
      columns = Math.max(columns, this.tableRows[r].cells.length);
    }
    const cells: EditableCell[] = [];
    for (let c = 0; c < columns; c++) {
      cells.push(new EditableCell('', 1, 1, false, false, null));
    }
    this.tableRows.push(new EditableRow(cells));
    this.tableRows = this.tableRows.slice();
  }

  private addTableColumn(): void {
    if (!this.canChangeTableShape()) {
      return;
    }
    for (let r = 0; r < this.tableRows.length; r++) {
      this.tableRows[r].cells.push(new EditableCell('', 1, 1, false, false, null));
    }
    this.tableRows = this.tableRows.slice();
  }

  private syncRowspans(): void {
    for (let r = 0; r < this.tableRows.length; r++) {
      const row: EditableRow = this.tableRows[r];
      for (let c = 0; c < row.cells.length; c++) {
        const cell: EditableCell = row.cells[c];
        if (cell.continuation || cell.rowSpan <= 1) {
          continue;
        }
        for (let offset = 1; offset < cell.rowSpan; offset++) {
          const targetRow: EditableRow | undefined = this.tableRows[r + offset];
          if (targetRow === undefined || c >= targetRow.cells.length) {
            continue;
          }
          const target: EditableCell = targetRow.cells[c];
          if (target.continuation) {
            target.text = cell.text;
            target.header = cell.header;
          }
        }
      }
    }
  }

  private buildTableBlock(): ContentBlock | null {
    this.syncRowspans();
    const rows: TableRow[] = [];
    for (let r = 0; r < this.tableRows.length; r++) {
      const cells: TableCell[] = [];
      const editableRow: EditableRow = this.tableRows[r];
      for (let c = 0; c < editableRow.cells.length; c++) {
        const cell: EditableCell = editableRow.cells[c];
        const source: TableCell | null = cell.source;
        const unchanged: boolean = source !== null && source.text() === cell.text;
        const segments: InlineSegment[] = unchanged ?
          (source as TableCell).segments : [new InlineSegment(cell.text)];
        const images: ImageData[] = unchanged ? (source as TableCell).images : [];
        const nextCell: TableCell = new TableCell(segments, cell.header, cell.colSpan,
          cell.rowSpan, images, cell.continuation, false);
        if (source !== null) {
          nextCell.align = source.align;
          nextCell.attrs = source.attrs;
        }
        cells.push(nextCell);
      }
      rows.push(new TableRow(cells, editableRow.cells.length > 0 &&
        editableRow.cells[0].header));
    }
    const table: TableData = new TableData(rows);
    if (this.block.table !== null) {
      table.caption = this.block.table.caption;
      table.columnWidths = this.block.table.columnWidths;
      table.headerRowCount = this.block.table.headerRowCount;
      table.footerRowCount = this.block.table.footerRowCount;
      table.attrs = this.block.table.attrs;
    }
    const next: ContentBlock = new ContentBlock(this.block.kind, this.block.text,
      this.block.level, this.block.codeLines, this.block.language, this.block.segments,
      this.block.listItems, table, this.block.image, this.block.listMarkers,
      this.block.callout, this.block.include, this.block.listLevels, this.block.indent,
      this.block.quoteBlocks, this.block.id, this.block.raw, this.block.source);
    next.attrs = this.block.attrs;
    next.children = this.block.children;
    next.dirty = true;
    next.serializeMode = 'model';
    return next;
  }

  private saveTable(): void {
    const next: ContentBlock | null = this.buildTableBlock();
    if (next !== null) {
      this.onSave(next);
    }
  }

  private autoSaveTable(): void {
    const next: ContentBlock | null = this.buildTableBlock();
    if (next !== null) {
      this.onAutoSave(next);
    }
  }

  private calloutAccent(type: string): string {
    if (type === 'warning') {
      return '#d99a2b';
    }
    if (type === 'success') {
      return '#3fa66a';
    }
    if (type === 'danger' || type === 'error') {
      return '#d9534f';
    }
    return '#4a90e2';
  }

  private addCalloutParagraph(): void {
    const block: ContentBlock = new ContentBlock(ContentBlockKind.PARAGRAPH, '', 0, [], '',
      [new InlineSegment('')]);
    block.dirty = true;
    this.calloutChildren.push(block);
    this.calloutChildren = this.calloutChildren.slice();
    this.calloutChildTick++;
  }

  private childText(block: ContentBlock): string {
    let text: string = '';
    for (let i = 0; i < block.segments.length; i++) {
      text += block.segments[i].text;
    }
    return text;
  }

  private updateCalloutParagraph(block: ContentBlock, value: string): void {
    block.text = value;
    block.segments = [new InlineSegment(value)];
    block.dirty = true;
  }

  private listText(block: ContentBlock): string {
    const lines: string[] = [];
    for (let i = 0; i < block.listItems.length; i++) {
      let line: string = '';
      const segments: InlineSegment[] = block.listItems[i];
      for (let s = 0; s < segments.length; s++) {
        line += segments[s].text;
      }
      lines.push(line);
    }
    return lines.join('\n');
  }

  private updateCalloutList(block: ContentBlock, value: string): void {
    const lines: string[] = value.split('\n');
    const items: InlineSegment[][] = [];
    const markers: string[] = [];
    const levels: number[] = [];
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i].replace(/^\s*(?:[-*+]|\d+\.)\s*/, '');
      items.push([new InlineSegment(line)]);
      markers.push('•');
      levels.push(0);
    }
    block.listItems = items;
    block.listMarkers = markers;
    block.listLevels = levels;
    block.dirty = true;
  }

  private saveCallout(): void {
    if (this.block.callout === null) {
      return;
    }
    const old: CalloutData = this.block.callout;
    const children: ContentBlock[] = this.calloutChildren.slice();
    const callout: CalloutData = new CalloutData(this.calloutType,
      old.icon, this.calloutAccent(this.calloutType), children, this.calloutTitle.trim());
    const next: ContentBlock = new ContentBlock(this.block.kind, this.block.text,
      this.block.level, this.block.codeLines, this.block.language, this.block.segments,
      this.block.listItems, this.block.table, this.block.image, this.block.listMarkers,
      callout, this.block.include, this.block.listLevels, this.block.indent,
      this.block.quoteBlocks, this.block.id, this.block.raw, this.block.source);
    next.attrs = this.block.attrs;
    next.children = children;
    next.dirty = true;
    next.serializeMode = 'model';
    this.onSave(next);
  }

  private save(): void {
    if (this.rawMode) {
      this.saveRaw();
    } else if (this.block.kind === ContentBlockKind.TABLE) {
      this.saveTable();
    } else if (this.block.kind === ContentBlockKind.CALLOUT) {
      this.saveCallout();
    } else {
      this.saveImage();
    }
  }

  @Builder
  private CalloutPanel() {
    Column({ space: 10 }) {
      Text('类型')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
      Row({ space: 6 }) {
        ForEach(['note', 'info', 'warning', 'success', 'danger'],
          (type: string, index: number) => {
            Text(type === 'note' ? 'Note' : type === 'info' ? 'Info' :
              type === 'warning' ? 'Warning' : type === 'success' ? 'Success' : 'Danger')
              .fontSize(11)
              .fontColor(this.calloutType === type ? $r('app.color.primary') :
                $r('app.color.text_secondary'))
              .padding({ left: 9, right: 9, top: 5, bottom: 5 })
              .borderRadius(6)
              .backgroundColor(this.calloutType === type ? $r('app.color.primary_soft') :
                $r('app.color.bg_secondary'))
              .onClick(() => {
                this.calloutType = type;
              })
          }, (type: string, index: number) => `callout-type-${type}`)
      }
      .width('100%')

      TextInput({ text: this.calloutTitle, placeholder: 'Callout 标题' })
        .width('100%')
        .height(38)
        .fontSize(13)
        .onChange((value: string) => {
          this.calloutTitle = value;
        })

      Scroll() {
        Column({ space: 8 }) {
          ForEach(this.calloutChildren, (child: ContentBlock, index: number) => {
            if (child.kind === ContentBlockKind.PARAGRAPH) {
              TextInput({ text: this.childText(child), placeholder: '段落内容' })
                .width('100%')
                .constraintSize({ minHeight: 36, maxHeight: 120 })
                .fontSize(13)
                .onChange((value: string) => {
                  this.updateCalloutParagraph(child, value);
                })
            } else if (child.kind === ContentBlockKind.LIST) {
              TextArea({ text: this.listText(child), placeholder: '每行一个列表项' })
                .width('100%')
                .constraintSize({ minHeight: 70, maxHeight: 180 })
                .fontSize(13)
                .backgroundColor($r('app.color.bg_secondary'))
                .borderRadius(6)
                .onChange((value: string) => {
                  this.updateCalloutList(child, value);
                })
            } else {
              Text('[复杂块暂不支持嵌套编辑]')
                .width('100%')
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
                .padding(10)
                .backgroundColor($r('app.color.bg_secondary'))
                .borderRadius(6)
            }
          }, (child: ContentBlock, index: number) =>
            `${index}-${child.kind}-${this.calloutChildTick}`)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      Row({ space: 10 }) {
        Text('+ 添加段落')
          .fontSize(12)
          .fontColor($r('app.color.primary'))
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(6)
          .backgroundColor($r('app.color.primary_soft'))
          .onClick(() => {
            this.addCalloutParagraph();
          })
        Blank()
        Text('高级：原始 HTML')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .onClick(() => {
            this.rawMode = true;
          })
      }
      .width('100%')
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private TablePanel() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('添加行')
          .fontSize(12)
          .fontColor($r('app.color.primary'))
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(6)
          .backgroundColor($r('app.color.primary_soft'))
          .onClick(() => {
            this.addTableRow();
          })
        Text('添加列')
          .fontSize(12)
          .fontColor(this.canChangeTableShape() ? $r('app.color.primary') :
            $r('app.color.text_tertiary'))
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(6)
          .backgroundColor(this.canChangeTableShape() ? $r('app.color.primary_soft') :
            $r('app.color.bg_secondary'))
          .onClick(() => {
            this.addTableColumn();
          })
        Blank()
        Text('高级：原始 HTML')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .onClick(() => {
            this.rawMode = true;
          })
      }
      .width('100%')

      Text('跨行/跨列、表头与单元格图片会保留；复杂表格暂不支持增删行列。')
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))

      Scroll(this.tableScroller) {
        Column({ space: 1 }) {
          ForEach(this.tableRows, (row: EditableRow, rowIndex: number) => {
            Row({ space: 1 }) {
              ForEach(row.cells, (cell: EditableCell, cellIndex: number) => {
                if (cell.continuation) {
                  Column() {
                    Text('↳')
                      .fontSize(11)
                      .fontColor($r('app.color.text_tertiary'))
                  }
                  .width(126 * Math.max(cell.colSpan, 1))
                  .height(62)
                  .padding(4)
                  .backgroundColor($r('app.color.bg_secondary'))
                  .border({ width: 1, color: $r('app.color.table_cell_border') })
                } else {
                  Column({ space: 4 }) {
                    TextInput({ text: cell.text, placeholder: '单元格' })
                      .width('100%')
                      .height(32)
                      .fontSize(12)
                      .onFocus(() => {
                        this.scrollTableTo(rowIndex);
                      })
                      .onBlur(() => {
                        this.autoSaveTable();
                      })
                      .onChange((value: string) => {
                        cell.text = value;
                      })
                    Row({ space: 6 }) {
                      Text(cell.header ? '表头' : '普通')
                        .fontSize(10)
                        .fontColor(cell.header ? $r('app.color.primary') :
                          $r('app.color.text_tertiary'))
                        .onClick(() => {
                          cell.header = !cell.header;
                          this.tableRows = this.tableRows.slice();
                        })
                      if (cell.colSpan > 1 || cell.rowSpan > 1) {
                        Text(`${cell.colSpan}×${cell.rowSpan}`)
                          .fontSize(10)
                          .fontColor($r('app.color.text_tertiary'))
                      }
                    }
                  }
                  .width(126 * Math.max(cell.colSpan, 1))
                  .height(62)
                  .padding(4)
                  .backgroundColor(cell.header ? $r('app.color.table_header_bg') :
                    $r('app.color.bg_primary'))
                  .border({ width: 1, color: $r('app.color.table_cell_border') })
                }
              }, (cell: EditableCell, cellIndex: number) =>
                `${rowIndex}-${cellIndex}-${cell.text}-${cell.header}`)
            }
          }, (row: EditableRow, rowIndex: number) => `table-row-${rowIndex}`)
        }
      }
      .scrollable(ScrollDirection.Vertical)
      .padding({ bottom: this.keyboardInset })
      .scrollBar(BarState.Off)
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
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
      } else if (this.block.kind === ContentBlockKind.TABLE && !this.rawMode) {
        this.TablePanel()
      } else if (this.block.kind === ContentBlockKind.CALLOUT && !this.rawMode) {
        this.CalloutPanel()
      } else {
        this.RawPanel()
        if (this.block.kind === ContentBlockKind.IMAGE ||
          this.block.kind === ContentBlockKind.TABLE ||
          this.block.kind === ContentBlockKind.CALLOUT) {
          Text(this.block.kind === ContentBlockKind.TABLE ? '返回表格编辑' :
            (this.block.kind === ContentBlockKind.CALLOUT ? '返回 Callout 编辑' : '返回属性面板'))
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
