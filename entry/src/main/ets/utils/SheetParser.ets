import { ParsedSheet, SheetCell, SheetRow } from '../models/SheetModels';

interface UniverColor {
  rgb?: string;
}

interface UniverDecoration {
  s?: number;
}

interface UniverNumberFormat {
  pattern?: string;
}

interface UniverBorderEdge {
  s?: number;
  cl?: UniverColor;
}

interface UniverBorderData {
  t?: UniverBorderEdge;
  r?: UniverBorderEdge;
  b?: UniverBorderEdge;
  l?: UniverBorderEdge;
}

interface UniverStyle {
  bg?: UniverColor;
  fc?: UniverColor;
  cl?: UniverColor;
  bl?: number;
  it?: number;
  fs?: number;
  tb?: number;
  bd?: UniverBorderData;
  st?: UniverDecoration;
  ul?: UniverDecoration;
  n?: UniverNumberFormat;
}

interface UniverCell {
  v?: string | number | boolean;
  m?: string;
  f?: string;
  t?: number;
  s?: string | UniverStyle;
}

interface UniverColumn {
  w?: number;
}

interface UniverRow {
  h?: number;
  // Univer's row filter flag. It is deliberately parsed but never applied:
  // the reader always renders the complete row set.
  hd?: number;
  isHidden?: boolean;
  hidden?: boolean;
}

interface UniverMerge {
  startRow?: number;
  endRow?: number;
  startColumn?: number;
  endColumn?: number;
}

interface UniverSheet {
  id?: string;
  name?: string;
  rowCount?: number;
  columnCount?: number;
  defaultColumnWidth?: number;
  defaultRowHeight?: number;
  cellData?: Record<string, Record<string, UniverCell>>;
  columnData?: Record<string, UniverColumn>;
  rowData?: Record<string, UniverRow>;
  mergeData?: UniverMerge[];
}

interface UniverResource {
  name?: string;
  data?: string;
}

interface UniverWorkbook {
  sheetOrder?: string[];
  sheets?: Record<string, UniverSheet>;
  styles?: Record<string, UniverStyle>;
  resources?: UniverResource[];
}

interface UniverPayload extends UniverWorkbook {
  version?: number;
  workbook?: UniverWorkbook;
}

interface DvRange {
  startColumn?: number;
  endColumn?: number;
  startRow?: number;
  endRow?: number;
}

interface DvRule {
  type?: string;
  formula1?: string;
  formula2?: string;
  ranges?: DvRange[];
}

class TagColor {
  bg: string;
  fc: string;

  constructor(bg: string, fc: string) {
    this.bg = bg;
    this.fc = fc;
  }
}

class RangeReference {
  sheetName: string;
  startColumn: number;
  startRow: number;
  endColumn: number;
  endRow: number;

  constructor(sheetName: string, startColumn: number, startRow: number,
    endColumn: number, endRow: number) {
    this.sheetName = sheetName;
    this.startColumn = startColumn;
    this.startRow = startRow;
    this.endColumn = endColumn;
    this.endRow = endRow;
  }
}

export class SheetParser {
  private static readonly DEFAULT_BG: string = '#1E1F22';
  private static readonly DEFAULT_FC: string = '#CCCCCC';
  private static readonly HEADER_BG: string = '#2D2D30';
  private static readonly HEADER_FC: string = '#FFFFFF';

  static sheetNames(content: string): string[] {
    const parsed: UniverPayload = JSON.parse(content) as UniverPayload;
    const workbook: UniverWorkbook = parsed.workbook !== undefined ? parsed.workbook : parsed;
    const sheets: Record<string, UniverSheet> = workbook.sheets !== undefined ? workbook.sheets : {};
    const order: string[] = workbook.sheetOrder !== undefined && workbook.sheetOrder.length > 0
      ? workbook.sheetOrder : Object.keys(sheets);
    const names: string[] = [];
    for (let i: number = 0; i < order.length; i++) {
      const sheet: UniverSheet | undefined = sheets[order[i]];
      names.push(sheet !== undefined && sheet.name !== undefined ? sheet.name : `Sheet${i + 1}`);
    }
    return names;
  }

  static parse(content: string, sheetIndex: number = 0): ParsedSheet {
    const parsed: UniverPayload = JSON.parse(content) as UniverPayload;
    const workbook: UniverWorkbook = parsed.workbook !== undefined ? parsed.workbook : parsed;
    const sheets: Record<string, UniverSheet> = workbook.sheets !== undefined ? workbook.sheets : {};
    const order: string[] = workbook.sheetOrder !== undefined && workbook.sheetOrder.length > 0
      ? workbook.sheetOrder : Object.keys(sheets);
    if (order.length === 0) {
      return new ParsedSheet();
    }
    const safeIndex: number = Math.min(Math.max(sheetIndex, 0), order.length - 1);
    const sheetId: string = order[safeIndex];
    const sheet: UniverSheet = sheets[sheetId] !== undefined ? sheets[sheetId] : {};
    const styles: Record<string, UniverStyle> = workbook.styles !== undefined ? workbook.styles : {};
    const cellData: Record<string, Record<string, UniverCell>> =
      sheet.cellData !== undefined ? sheet.cellData : {};

    let maxUsedRow: number = 0;
    let maxUsedCol: number = 0;
    const rowKeys: string[] = Object.keys(cellData);
    for (let rIndex: number = 0; rIndex < rowKeys.length; rIndex++) {
      const rowKey: string = rowKeys[rIndex];
      const row: Record<string, UniverCell> = cellData[rowKey];
      if (row === undefined) {
        continue;
      }
      const colKeys: string[] = Object.keys(row);
      for (let cIndex: number = 0; cIndex < colKeys.length; cIndex++) {
        const cell: UniverCell = row[colKeys[cIndex]];
        if (cell === undefined) {
          continue;
        }
        const value: string = SheetParser.cellValue(cell);
        if (value.length === 0 && (cell.f === undefined || cell.f.length === 0)) {
          continue;
        }
        const rowNumber: number = Number(rowKey);
        const colNumber: number = Number(colKeys[cIndex]);
        if (!isNaN(rowNumber) && rowNumber + 1 > maxUsedRow) {
          maxUsedRow = rowNumber + 1;
        }
        if (!isNaN(colNumber) && colNumber + 1 > maxUsedCol) {
          maxUsedCol = colNumber + 1;
        }
      }
    }

    const merges: UniverMerge[] = sheet.mergeData !== undefined ? sheet.mergeData : [];
    for (let mergeIndex: number = 0; mergeIndex < merges.length; mergeIndex++) {
      const merge: UniverMerge = merges[mergeIndex];
      if (merge.endRow !== undefined && merge.endRow + 1 > maxUsedRow) {
        maxUsedRow = merge.endRow + 1;
      }
      if (merge.endColumn !== undefined && merge.endColumn + 1 > maxUsedCol) {
        maxUsedCol = merge.endColumn + 1;
      }
    }

    // A column can exist even when its cellData key is not present (for
    // example a column whose values are all formulas or hidden by a view).
    const sheetColumnData: Record<string, UniverColumn> =
      sheet.columnData !== undefined ? sheet.columnData : {};
    const columnKeys: string[] = Object.keys(sheetColumnData);
    for (let i: number = 0; i < columnKeys.length; i++) {
      const columnNumber: number = Number(columnKeys[i]);
      if (!isNaN(columnNumber) && columnNumber + 1 > maxUsedCol) {
        maxUsedCol = columnNumber + 1;
      }
    }

    const rowCount: number = maxUsedRow > 0 ? maxUsedRow + 2 : 3;
    const colCount: number = maxUsedCol > 0 ? maxUsedCol : 1;
    const tagMap: Map<number, Map<string, TagColor>> = SheetParser.buildTagMap(workbook, sheet, sheetId);

    const cells: SheetCell[][] = [];
    for (let row: number = 0; row < rowCount; row++) {
      const rowCells: SheetCell[] = [];
      for (let col: number = 0; col < colCount; col++) {
        rowCells.push(new SheetCell('', SheetParser.DEFAULT_BG, SheetParser.DEFAULT_FC));
      }
      cells.push(rowCells);
    }

    // Univer cellData is sparse: keys are string row/column indexes. Walk the
    // absolute matrix and write cells[row][col]; never append by iteration
    // order, otherwise an empty column would collapse and shift the next one.
    for (let rowNumber: number = 0; rowNumber < maxUsedRow; rowNumber++) {
      const sourceRow: Record<string, UniverCell> | undefined = cellData[`${rowNumber}`];
      for (let colNumber: number = 0; colNumber < maxUsedCol; colNumber++) {
        const sourceCell: UniverCell | undefined =
          sourceRow !== undefined ? sourceRow[`${colNumber}`] : undefined;
        if (sourceCell === undefined) {
          continue;
        }
        const target: SheetCell = cells[rowNumber][colNumber];
        const style: UniverStyle = SheetParser.resolveStyle(styles, sourceCell.s);
        target.value = SheetParser.displayValue(sourceCell, style);
        SheetParser.applyStyle(target, style);
        if (rowNumber === 0) {
          target.bg = SheetParser.HEADER_BG;
          target.fc = SheetParser.HEADER_FC;
          target.bold = true;
          target.wrap = false;
        }
        const tag: TagColor | undefined = tagMap.get(colNumber)?.get(target.value);
        if (tag !== undefined) {
          target.bg = tag.bg;
          target.fc = tag.fc;
          target.bold = true;
        }
      }
    }

    for (let mergeIndex: number = 0; mergeIndex < merges.length; mergeIndex++) {
      const merge: UniverMerge = merges[mergeIndex];
      if (merge.startRow === undefined || merge.startColumn === undefined ||
        merge.endRow === undefined || merge.endColumn === undefined) {
        continue;
      }
      if (merge.startRow >= rowCount || merge.startColumn >= colCount) {
        continue;
      }
      const top: SheetCell = cells[merge.startRow][merge.startColumn];
      top.rowSpan = Math.min(rowCount - merge.startRow, merge.endRow - merge.startRow + 1);
      top.colSpan = Math.min(colCount - merge.startColumn, merge.endColumn - merge.startColumn + 1);
      for (let row: number = merge.startRow; row <= merge.endRow && row < rowCount; row++) {
        for (let col: number = merge.startColumn; col <= merge.endColumn && col < colCount; col++) {
          if (row === merge.startRow && col === merge.startColumn) {
            continue;
          }
          cells[row][col].covered = true;
          cells[row][col].value = '';
          cells[row][col].bg = top.bg;
        }
      }
    }

    const columnData: Record<string, UniverColumn> = sheet.columnData !== undefined ? sheet.columnData : {};
    const defaultWidth: number = sheet.defaultColumnWidth !== undefined ? sheet.defaultColumnWidth : 90;
    const columnWidths: number[] = [];
    for (let col: number = 0; col < colCount; col++) {
      const column: UniverColumn | undefined = columnData[`${col}`];
      let width: number = column !== undefined && column.w !== undefined ? column.w : defaultWidth;
      if (!isFinite(width) || width <= 0) {
        width = defaultWidth;
      }
      columnWidths.push(Math.round(Math.max(48, width)));
    }

    const rowData: Record<string, UniverRow> = sheet.rowData !== undefined ? sheet.rowData : {};
    const rowHeights: number[] = [];
    for (let row: number = 0; row < rowCount; row++) {
      if (row === 0) {
        rowHeights.push(38);
        continue;
      }
      let lines: number = 1;
      for (let col: number = 0; col < colCount; col++) {
        const cell: SheetCell = cells[row][col];
        if (!cell.wrap || cell.value.length === 0) {
          continue;
        }
        const charsPerLine: number = Math.max(1, Math.floor((columnWidths[col] - 12) / cell.fontSize));
        const cellLines: number = Math.min(3, Math.max(1, Math.ceil(cell.value.length / charsPerLine)));
        if (cellLines > lines) {
          lines = cellLines;
        }
      }
      const configured: UniverRow | undefined = rowData[`${row}`];
      const configuredHeight: number = configured !== undefined && configured.h !== undefined ? configured.h : 0;
      rowHeights.push(Math.round(Math.max(configuredHeight, 28, lines * 18 + 10)));
    }

    const columnLabels: string[] = [];
    for (let col: number = 0; col < colCount; col++) {
      columnLabels.push(SheetParser.columnLabel(col));
    }
    const rowLabels: string[] = [];
    for (let row: number = 0; row < rowCount; row++) {
      rowLabels.push(`${row + 1}`);
    }

    const rows: SheetRow[] = [];
    for (let row: number = 0; row < rowCount; row++) {
      rows.push(new SheetRow(row, cells[row]));
    }

    const result: ParsedSheet = new ParsedSheet();
    result.name = sheet.name !== undefined ? sheet.name : '';
    result.cells = cells;
    result.rows = rows;
    result.columnWidths = columnWidths;
    result.rowHeights = rowHeights;
    result.columnLabels = columnLabels;
    result.rowLabels = rowLabels;
    return result;
  }

  private static displayValue(cell: UniverCell, style: UniverStyle): string {
    if (style.n !== undefined && style.n.pattern !== undefined &&
      typeof cell.v === 'number' && /[yMdHhms]/.test(style.n.pattern)) {
      return SheetParser.formatExcelDate(cell.v, style.n.pattern);
    }
    return SheetParser.cellValue(cell);
  }

  private static formatExcelDate(serial: number, pattern: string): string {
    const millis: number = Math.round((serial - 25569) * 86400 * 1000);
    const date: Date = new Date(millis);
    const pad: (value: number) => string = (value: number): string => {
      return value < 10 ? `0${value}` : `${value}`;
    };
    return pattern
      .replace(/yyyy/g, `${date.getUTCFullYear()}`)
      .replace(/MM/g, pad(date.getUTCMonth() + 1))
      .replace(/dd/g, pad(date.getUTCDate()))
      .replace(/hh/g, pad(date.getUTCHours()))
      .replace(/mm/g, pad(date.getUTCMinutes()))
      .replace(/ss/g, pad(date.getUTCSeconds()));
  }

  private static cellValue(cell: UniverCell): string {
    if (cell.m !== undefined && cell.m.length > 0) {
      return cell.m;
    }
    if (cell.v === undefined) {
      return '';
    }
    return `${cell.v}`;
  }

  private static resolveStyle(styles: Record<string, UniverStyle>,
    styleRef: string | UniverStyle | undefined): UniverStyle {
    if (typeof styleRef === 'string') {
      const found: UniverStyle | undefined = styles[styleRef];
      return found !== undefined ? found : {};
    }
    return styleRef !== undefined ? styleRef : {};
  }

  private static applyStyle(target: SheetCell, style: UniverStyle): void {
    if (style.bg !== undefined && style.bg.rgb !== undefined) {
      target.bg = style.bg.rgb;
    }
    if (style.fc !== undefined && style.fc.rgb !== undefined) {
      target.fc = style.fc.rgb;
    } else if (style.cl !== undefined && style.cl.rgb !== undefined) {
      target.fc = style.cl.rgb;
    }
    if (style.bl === 1) {
      target.bold = true;
    }
    if (style.fs !== undefined && style.fs > 0) {
      target.fontSize = style.fs;
    }
    if (style.tb === 3) {
      target.wrap = true;
    }
  }

  private static columnLabel(index: number): string {
    let value: number = index;
    let label: string = '';
    while (value >= 0) {
      label = String.fromCharCode(65 + value % 26) + label;
      value = Math.floor(value / 26) - 1;
    }
    return label;
  }

  private static buildTagMap(workbook: UniverWorkbook, sheet: UniverSheet,
    sheetId: string): Map<number, Map<string, TagColor>> {
    const result: Map<number, Map<string, TagColor>> = new Map();
    const resources: UniverResource[] = workbook.resources !== undefined ? workbook.resources : [];
    let resource: UniverResource | undefined = undefined;
    for (let i: number = 0; i < resources.length; i++) {
      if (resources[i].name === 'SHEET_DATA_VALIDATION_PLUGIN') {
        resource = resources[i];
      }
    }
    if (resource === undefined || resource.data === undefined) {
      return result;
    }
    let allRules: Record<string, DvRule[]> = {};
    try {
      allRules = JSON.parse(resource.data) as Record<string, DvRule[]>;
    } catch (error) {
      return result;
    }
    const currentRules: DvRule[] = allRules[sheetId] !== undefined ? allRules[sheetId] : [];
    SheetParser.collectRuleColors(workbook, currentRules, result);
    const sheetIds: string[] = Object.keys(allRules);
    for (let i: number = 0; i < sheetIds.length; i++) {
      if (sheetIds[i] === sheetId) {
        continue;
      }
      const rules: DvRule[] = allRules[sheetIds[i]];
      for (let ruleIndex: number = 0; ruleIndex < rules.length; ruleIndex++) {
        const rule: DvRule = rules[ruleIndex];
        const ranges: DvRange[] = rule.ranges !== undefined ? rule.ranges : [];
        for (let rangeIndex: number = 0; rangeIndex < ranges.length; rangeIndex++) {
          const col: number | undefined = ranges[rangeIndex].startColumn;
          if (col === undefined || result.has(col)) {
            continue;
          }
          const options: string[] = SheetParser.optionsForRule(workbook, rule);
          const colors: string[] = SheetParser.colorsForRule(rule);
          if (options.length === 0 || colors.length === 0) {
            continue;
          }
          result.set(col, SheetParser.tagColors(options, colors));
        }
      }
    }
    return result;
  }

  private static collectRuleColors(workbook: UniverWorkbook, rules: DvRule[],
    result: Map<number, Map<string, TagColor>>): void {
    for (let ruleIndex: number = 0; ruleIndex < rules.length; ruleIndex++) {
      const rule: DvRule = rules[ruleIndex];
      const ranges: DvRange[] = rule.ranges !== undefined ? rule.ranges : [];
      const options: string[] = SheetParser.optionsForRule(workbook, rule);
      const colors: string[] = SheetParser.colorsForRule(rule);
      if (options.length === 0 || colors.length === 0) {
        continue;
      }
      for (let rangeIndex: number = 0; rangeIndex < ranges.length; rangeIndex++) {
        const col: number | undefined = ranges[rangeIndex].startColumn;
        if (col !== undefined && !result.has(col)) {
          result.set(col, SheetParser.tagColors(options, colors));
        }
      }
    }
  }

  private static optionsForRule(workbook: UniverWorkbook, rule: DvRule): string[] {
    const formula: string = rule.formula1 !== undefined ? rule.formula1 : '';
    if (formula.startsWith('[')) {
      try {
        const inline: string[] = JSON.parse(formula) as string[];
        return inline;
      } catch (error) {
        return [];
      }
    }
    const reference: RangeReference | null = SheetParser.parseReference(formula);
    if (reference === null) {
      return [];
    }
    const target: UniverSheet | null = SheetParser.findSheet(workbook, reference.sheetName);
    if (target === null) {
      return [];
    }
    const cellData: Record<string, Record<string, UniverCell>> =
      target.cellData !== undefined ? target.cellData : {};
    const values: string[] = [];
    for (let row: number = reference.startRow; row <= reference.endRow; row++) {
      const sourceRow: Record<string, UniverCell> | undefined = cellData[`${row}`];
      if (sourceRow === undefined) {
        continue;
      }
      for (let col: number = reference.startColumn; col <= reference.endColumn; col++) {
        const cell: UniverCell | undefined = sourceRow[`${col}`];
        if (cell === undefined) {
          continue;
        }
        const text: string = SheetParser.cellValue(cell);
        if (text.length > 0 && values.indexOf(text) < 0) {
          values.push(text);
        }
      }
    }
    return values;
  }

  private static colorsForRule(rule: DvRule): string[] {
    const formula: string = rule.formula2 !== undefined ? rule.formula2 : '';
    if (formula.length === 0) {
      return [];
    }
    const parts: string[] = formula.split(',');
    const colors: string[] = [];
    for (let i: number = 0; i < parts.length; i++) {
      const color: string = parts[i].trim();
      if (/^#[0-9a-fA-F]{6}$/.test(color)) {
        colors.push(color);
      }
    }
    return colors;
  }

  private static tagColors(options: string[], colors: string[]): Map<string, TagColor> {
    const map: Map<string, TagColor> = new Map();
    for (let i: number = 0; i < options.length; i++) {
      const color: string | undefined = colors[i];
      if (color !== undefined) {
        map.set(options[i], new TagColor(color, SheetParser.contrastColor(color)));
      }
    }
    return map;
  }

  private static contrastColor(background: string): string {
    const hex: string = background.replace('#', '');
    if (hex.length !== 6) {
      return SheetParser.DEFAULT_FC;
    }
    const r: number = parseInt(hex.substring(0, 2), 16);
    const g: number = parseInt(hex.substring(2, 4), 16);
    const b: number = parseInt(hex.substring(4, 6), 16);
    const luminance: number = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
    return luminance > 0.58 ? SheetParser.DEFAULT_BG : '#FFFFFF';
  }

  private static findSheet(workbook: UniverWorkbook, name: string): UniverSheet | null {
    const sheets: Record<string, UniverSheet> = workbook.sheets !== undefined ? workbook.sheets : {};
    const ids: string[] = Object.keys(sheets);
    for (let i: number = 0; i < ids.length; i++) {
      if (sheets[ids[i]].name === name) {
        return sheets[ids[i]];
      }
    }
    const base: string = name.split('-')[0];
    for (let i: number = 0; i < ids.length; i++) {
      if (sheets[ids[i]].name === base) {
        return sheets[ids[i]];
      }
    }
    return null;
  }

  private static parseReference(formula: string): RangeReference | null {
    const text: string = formula.trim().replace(/^=/, '');
    const match: RegExpMatchArray | null =
      text.match(/^'?([^'!]+)'?!\$?([A-Z]+)\$?(\d+):\$?([A-Z]+)\$?(\d+)$/);
    if (match === null) {
      return null;
    }
    return new RangeReference(match[1], SheetParser.columnIndex(match[2]),
      parseInt(match[3], 10) - 1, SheetParser.columnIndex(match[4]), parseInt(match[5], 10) - 1);
  }

  private static columnIndex(letters: string): number {
    let index: number = 0;
    for (let i: number = 0; i < letters.length; i++) {
      index = index * 26 + (letters.charCodeAt(i) - 64);
    }
    return index - 1;
  }
}
