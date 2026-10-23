import { ParsedSheet, SheetCell, SheetRow } from '../models/SheetModels';
import { SheetParser } from '../utils/SheetParser';

class SheetCellItem {
  row: number;
  col: number;
  cell: SheetCell;

  constructor(row: number, col: number, cell: SheetCell) {
    this.row = row;
    this.col = col;
    this.cell = cell;
  }
}

class SheetGridDataSource implements IDataSource {
  private items: SheetCellItem[];
  private listeners: DataChangeListener[] = [];

  constructor(items: SheetCellItem[]) {
    this.items = items;
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): SheetCellItem {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  notifyDataReload(): void {
    for (let i: number = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }
}

/**
 * Read-only native spreadsheet.
 *
 * The table is deliberately NOT internally vertically scrollable: the outer
 * note Scroll owns vertical gestures, while this component only owns the
 * horizontal scroller. A/B/C and every data row (including row 0) live in the
 * same Grid, so the complete table scrolls with the note.
 */
@Component
export struct NativeSheetView {
  @Prop @Watch('onContentChanged') content: string = '';
  @Prop noteId: string = '';
  @Prop @Watch('onSheetIndexChanged') sheetIndex: number = 0;
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;

  @State private parsed: ParsedSheet = new ParsedSheet();
  @State private gridItems: SheetCellItem[] = [];
  @State private selectedRow: number = -1;
  @State private selectedCol: number = -1;
  @State private loadError: string = '';
  @State private viewportWidth: number = 0;

  private bodyXScroller: Scroller = new Scroller();
  private gridSource: SheetGridDataSource = new SheetGridDataSource([]);

  private static readonly ROW_LABEL_WIDTH: number = 48;
  private static readonly COLUMN_LABEL_HEIGHT: number = 24;
  private static readonly BOTTOM_SPACER: number = 60;

  private isDark(): boolean {
    return this.colorMode !== 1;
  }

  private selectionColor(): ResourceColor {
    return $r('app.color.sheet_selection');
  }

  private sheetBg(): ResourceColor {
    return $r('app.color.sheet_bg');
  }

  private sheetText(): ResourceColor {
    return $r('app.color.sheet_text');
  }

  private headerBg(): ResourceColor {
    return $r('app.color.sheet_header_bg');
  }

  private headerText(): ResourceColor {
    return $r('app.color.sheet_header_text');
  }

  private gridLine(): ResourceColor {
    return $r('app.color.sheet_grid');
  }

  private onContentChanged(): void {
    this.reload();
  }

  private onSheetIndexChanged(): void {
    this.reload();
    this.selectedRow = -1;
    this.selectedCol = -1;
    setTimeout(() => {
      this.bodyXScroller.scrollTo({ xOffset: 0, yOffset: 0 });
    }, 0);
  }

  private onColorModeChanged(): void {
    this.reload();
  }

  aboutToAppear(): void {
    this.reload();
  }

  private reload(): void {
    try {
      const source: string = this.content.length > 0 ? this.content : '{}';
      this.parsed = SheetParser.parse(source, this.sheetIndex);
      if (!this.isDark()) {
        this.applyLightTheme(this.parsed);
      }
      this.rebuildGridSource();
      this.loadError = '';
    } catch (error) {
      this.parsed = new ParsedSheet();
      this.gridItems = [];
      this.gridSource = new SheetGridDataSource([]);
      this.loadError = '电子表格解析失败';
    }
  }

  private rebuildGridSource(): void {
    const items: SheetCellItem[] = [];
    for (let row: number = 0; row < this.parsed.rows.length; row++) {
      const sheetRow: SheetRow = this.parsed.rows[row];
      for (let col: number = 0; col < sheetRow.cells.length; col++) {
        items.push(new SheetCellItem(row, col, sheetRow.cells[col]));
      }
    }
    this.gridItems = items;
    this.gridSource = new SheetGridDataSource(items);
  }

  private applyLightTheme(sheet: ParsedSheet): void {
    for (let row: number = 0; row < sheet.cells.length; row++) {
      const cells: SheetCell[] = sheet.cells[row];
      for (let col: number = 0; col < cells.length; col++) {
        const cell: SheetCell = cells[col];
        if (cell.bg === '#1E1F22') {
          cell.bg = '#FFFFFF';
        } else if (cell.bg === '#2D2D30') {
          cell.bg = '#F5F5F5';
        }
        if (cell.fc === '#CCCCCC') {
          cell.fc = '#333333';
        } else if (cell.fc === '#FFFFFF') {
          cell.fc = '#1A1A1A';
        }
        if (this.colorLuminance(cell.bg) > 0.72 && this.colorLuminance(cell.fc) > 0.65) {
          cell.fc = '#333333';
        }
      }
    }
  }

  private colorLuminance(color: string): number {
    const hex: string = color.replace('#', '');
    if (hex.length < 6) {
      return 0;
    }
    const r: number = parseInt(hex.substring(0, 2), 16);
    const g: number = parseInt(hex.substring(2, 4), 16);
    const b: number = parseInt(hex.substring(4, 6), 16);
    if (isNaN(r) || isNaN(g) || isNaN(b)) {
      return 0;
    }
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  }

  private totalWidth(): number {
    let total: number = 0;
    for (let i: number = 0; i < this.parsed.columnWidths.length; i++) {
      total += this.parsed.columnWidths[i];
    }
    return total;
  }

  private gridWidth(): number {
    return Math.max(this.totalWidth(),
      Math.max(0, this.viewportWidth - NativeSheetView.ROW_LABEL_WIDTH));
  }

  private scaledColumnWidth(index: number): number {
    const total: number = this.totalWidth();
    return total > 0 ? this.cellWidth(index) * this.gridWidth() / total : this.cellWidth(index);
  }

  private columnsTemplate(): string {
    const parts: string[] = [];
    for (let i: number = 0; i < this.parsed.columnWidths.length; i++) {
      parts.push(`${this.parsed.columnWidths[i]}fr`);
    }
    return parts.join(' ');
  }

  private gridHeight(): number {
    let total: number = 0;
    for (let i: number = 0; i < this.parsed.rowHeights.length; i++) {
      total += this.parsed.rowHeights[i];
    }
    return total;
  }

  private rowHeight(row: number): number {
    return row >= 0 && row < this.parsed.rowHeights.length ? this.parsed.rowHeights[row] : 30;
  }

  private cellWidth(col: number): number {
    return col >= 0 && col < this.parsed.columnWidths.length ? this.parsed.columnWidths[col] : 90;
  }

  private isSelected(row: number, col: number): boolean {
    return this.selectedRow === row && this.selectedCol === col;
  }

  private isColumnLabelSelected(col: number): boolean {
    return this.selectedRow === -1 && this.selectedCol === col;
  }

  private isRowLabelSelected(row: number): boolean {
    return this.selectedCol === -1 && this.selectedRow === row;
  }

  private select(row: number, col: number): void {
    this.selectedRow = row;
    this.selectedCol = col;
  }

  private selectColumn(col: number): void {
    this.selectedRow = -1;
    this.selectedCol = col;
  }

  private selectRow(row: number): void {
    this.selectedRow = row;
    this.selectedCol = -1;
  }

  @Builder
  private CellContent(cell: SheetCell, row: number, col: number) {
    Text(cell.value)
      .fontSize(cell.fontSize)
      .fontColor(cell.fc)
      .fontWeight(cell.bold ? FontWeight.Bold : FontWeight.Normal)
      .maxLines(cell.wrap ? 3 : 1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .textAlign(TextAlign.Start)
      .copyOption(CopyOptions.LocalDevice)
      .width('100%')
      .height('100%')
      .padding({ left: 6, right: 6, top: 4, bottom: 4 })
      .backgroundColor(cell.bg)
      .border(this.isSelected(row, col)
        ? { width: 2, color: this.selectionColor() }
        : { width: { right: 1, bottom: 1 }, color: this.gridLine() })
      .onClick(() => {
        this.select(row, col);
      })
  }

  @Builder
  private ColumnLabels() {
    Row() {
      ForEach(this.parsed.columnLabels, (label: string, index: number) => {
        Text(label)
          .fontSize(12)
          .fontColor(this.isColumnLabelSelected(index) ? this.selectionColor() : this.headerText())
          .fontWeight(FontWeight.Medium)
          .layoutWeight(this.cellWidth(index))
          .height(NativeSheetView.COLUMN_LABEL_HEIGHT)
          .textAlign(TextAlign.Center)
          .backgroundColor(this.headerBg())
          .border(this.isColumnLabelSelected(index)
            ? { width: 2, color: this.selectionColor() }
            : { width: { right: 1, bottom: 1 }, color: this.gridLine() })
          .onClick(() => {
            this.selectColumn(index);
          })
      }, (label: string, index: number) => `col-${index}-${label}`)
    }
    .width(this.gridWidth())
    .height(NativeSheetView.COLUMN_LABEL_HEIGHT)
  }

  @Builder
  private DataGridCell(item: SheetCellItem) {
    GridItem() {
      this.CellContent(item.cell, item.row, item.col)
    }
    .height(this.rowHeight(item.row))
  }

  build() {
    Column() {
      if (this.parsed.cells.length === 0) {
        Column() {
          Text(this.loadError.length > 0 ? this.loadError : '电子表格为空')
            .fontSize(13)
            .fontColor(this.sheetText())
        }
        .width('100%')
        .padding({ top: 80, bottom: 80 })
        .justifyContent(FlexAlign.Center)
      } else {
        Row() {
          Column() {
            Text('')
              .width(NativeSheetView.ROW_LABEL_WIDTH)
              .height(NativeSheetView.COLUMN_LABEL_HEIGHT)
              .backgroundColor(this.headerBg())
              .border({ width: { right: 1, bottom: 1 }, color: this.gridLine() })

            ForEach(this.parsed.rows, (row: SheetRow) => {
              Text(`${row.index + 1}`)
                .fontSize(12)
                .fontColor(this.isRowLabelSelected(row.index) ? this.selectionColor() : this.sheetText())
                .width(NativeSheetView.ROW_LABEL_WIDTH)
                .height(this.rowHeight(row.index))
                .textAlign(TextAlign.Center)
                .backgroundColor(this.sheetBg())
                .border(this.isRowLabelSelected(row.index)
                  ? { width: 2, color: this.selectionColor() }
                  : { width: { right: 1, bottom: 1 }, color: this.gridLine() })
                .onClick(() => {
                  this.selectRow(row.index);
                })
            }, (row: SheetRow) => `row-label-${row.index}`)
          }
          .width(NativeSheetView.ROW_LABEL_WIDTH)
          .alignItems(HorizontalAlign.Start)

          Scroll(this.bodyXScroller) {
            Column() {
              this.ColumnLabels()

              Grid() {
                if (this.parsed.rows.length > 50) {
                  LazyForEach(this.gridSource, (item: SheetCellItem) => {
                    this.DataGridCell(item)
                  }, (item: SheetCellItem) => `${item.row}-${item.col}`)
                } else {
                  ForEach(this.gridItems, (item: SheetCellItem) => {
                    this.DataGridCell(item)
                  }, (item: SheetCellItem) => `${item.row}-${item.col}`)
                }
              }
              .columnsTemplate(this.columnsTemplate())
              .columnsGap(0)
              .rowsGap(0)
              .width(this.gridWidth())
              .height(this.gridHeight())
              .scrollBar(BarState.Off)
              .edgeEffect(EdgeEffect.None)
            }
            .width(this.gridWidth())
            .alignItems(HorizontalAlign.Start)
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.On)
          .edgeEffect(EdgeEffect.None)
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .border({ width: { left: 1, top: 1 }, color: this.gridLine() })

        Blank()
          .height(NativeSheetView.BOTTOM_SPACER)
      }
    }
    .width('100%')
    .backgroundColor(this.sheetBg())
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const widthValue: number = parseFloat(newArea.width.toString());
      if (!isNaN(widthValue) && widthValue > 0) {
        this.viewportWidth = widthValue;
      }
    })
  }
}
