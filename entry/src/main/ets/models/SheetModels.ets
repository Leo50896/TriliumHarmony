/**
 * Native spreadsheet models. No WebView / HTML types are used here.
 */
export class SheetCell {
  value: string;
  bg: string;
  fc: string;
  bold: boolean;
  fontSize: number;
  wrap: boolean;
  rowSpan: number;
  colSpan: number;
  covered: boolean;

  constructor(value: string = '', bg: string = '#1E1F22', fc: string = '#CCCCCC',
    bold: boolean = false, fontSize: number = 13, wrap: boolean = false,
    rowSpan: number = 1, colSpan: number = 1, covered: boolean = false) {
    this.value = value;
    this.bg = bg;
    this.fc = fc;
    this.bold = bold;
    this.fontSize = fontSize;
    this.wrap = wrap;
    this.rowSpan = rowSpan;
    this.colSpan = colSpan;
    this.covered = covered;
  }
}

export class SheetRow {
  index: number;
  cells: SheetCell[];

  constructor(index: number, cells: SheetCell[]) {
    this.index = index;
    this.cells = cells;
  }
}

export class ParsedSheet {
  name: string = '';
  cells: SheetCell[][] = [];
  rows: SheetRow[] = [];
  columnWidths: number[] = [];
  rowHeights: number[] = [];
  columnLabels: string[] = [];
  rowLabels: string[] = [];
}
