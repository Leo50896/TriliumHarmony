import { ImageData, TableCell, TableData, TableRow } from '../utils/HtmlContentParser';
import { InlineTextView } from './InlineTextView';
import { TriliumImage } from './TriliumImage';
import { StateKeys } from '../constants/StateKeys';

/**
 * Native table approximation.
 *
 * ArkUI has no table component with border-collapse semantics, so the table is
 * built from Rows/Columns: 1vp outer border, 1vp right/bottom cell borders,
 * 7vp cell padding and the Trilium dark header background (#555555).
 *
 * Cells can contain inline text and images. Images are normal components in the
 * cell Column, so the row grows instead of clipping the image.
 */
@Component
export struct TriliumTable {
  @Prop table: TableData = new TableData([]);
  @StorageLink(StateKeys.READER_FONT_SIZE) private readerFontSize: number = 16;
  onLink: (href: string) => void = () => {};

  private scaledFont(base: number): number {
    return base * this.readerFontSize / 16;
  }

  private cellWeight(cell: TableCell, cellIndex: number): number {
    if (cell.colspan > 0) {
      return cell.colspan;
    }
    return cellIndex === 0 ? 1.8 : 1;
  }

  private cellTextColor(cell: TableCell): ResourceColor {
    if (cell.continuation) {
      return $r('app.color.table_continuation_text');
    }
    return cell.header ? $r('app.color.text_primary') : $r('app.color.text_primary');
  }

  @Builder
  private CellView(cell: TableCell, row: TableRow, rowIndex: number, cellIndex: number) {
    Column({ space: 4 }) {
      if (cell.segments.length > 0) {
        InlineTextView({
          segments: cell.segments,
          fontSize: this.scaledFont(15),
          lineHeight: this.scaledFont(23),
          color: this.cellTextColor(cell),
          weight: cell.header ? FontWeight.Medium : FontWeight.Normal,
          onLink: this.onLink
        })
      }
      ForEach(cell.images, (image: ImageData, imageIndex: number) => {
        TriliumImage({
          src: image.src,
          alt: image.alt,
          widthPercent: image.widthPercent
        })
      }, (image: ImageData, imageIndex: number) => `${imageIndex}-${image.src}`)
    }
    .layoutWeight(this.cellWeight(cell, cellIndex))
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .padding(7)
    .backgroundColor(cell.header ? $r('app.color.table_header_bg') :
      (cell.continuation ? $r('app.color.table_alt_bg') : Color.Transparent))
    .opacity(cell.placeholder ? 0.35 : 1)
    .border({
      width: {
        right: cellIndex < row.cells.length - 1 ? 1 : 0,
        bottom: rowIndex < this.table.rows.length - 1 ? 1 : 0
      },
      color: $r('app.color.table_cell_border')
    })
  }

  build() {
    Column() {
      ForEach(this.table.rows, (row: TableRow, rowIndex: number) => {
        Row() {
          ForEach(row.cells, (cell: TableCell, cellIndex: number) => {
            this.CellView(cell, row, rowIndex, cellIndex)
          }, (cell: TableCell, cellIndex: number) => `${rowIndex}-${cellIndex}-${cell.text()}`)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }, (row: TableRow, rowIndex: number) => `row-${rowIndex}`)
    }
    .width('100%')
    .border({ width: 1, color: $r('app.color.table_border') })
    .clip(true)
    .backgroundColor($r('app.color.bg_primary'))
    .margin({ top: 8, bottom: 8 })
  }
}
