import {
  ContentBlock,
  ContentBlockKind,
  HtmlContentParser,
  SourceSpan
} from '../HtmlContentParser';
import { MarkdownParser } from '../MarkdownParser';

/**
 * Line-preserving Markdown block scanner. Each block's raw text includes its
 * original line endings, so an untouched document serializes byte-for-byte.
 */
export class MarkdownBlockScanner {
  static scan(raw: string): ContentBlock[] {
    if (raw.length === 0) {
      return [];
    }
    const lines: string[] = raw.split('\n');
    const blocks: ContentBlock[] = [];
    let index: number = 0;
    let pending: string = '';

    while (index < lines.length) {
      if (lines[index].trim().length === 0) {
        if (index === lines.length - 1 && lines[index].length === 0) {
          index++;
          continue;
        }
        pending += lines[index] + '\n';
        index++;
        continue;
      }

      const startLine: number = index;
      const first: string = lines[index];

      if (/^```/.test(first.trim())) {
        index++;
        while (index < lines.length && !/^```/.test(lines[index].trim())) {
          index++;
        }
        if (index < lines.length) {
          index++;
        }
      } else if (MarkdownBlockScanner.isTableStart(lines, index)) {
        index += 2;
        while (index < lines.length && lines[index].trim().length > 0 &&
          lines[index].indexOf('|') >= 0) {
          index++;
        }
      } else if (/^#{1,6}\s/.test(first) || /^>\s?/.test(first) ||
        /^\s*([-*+]|\d+\.)\s+/.test(first) || /^\s*(---+|\*\*\*+|___+)\s*$/.test(first)) {
        index++;
      } else {
        index++;
        while (index < lines.length && lines[index].trim().length > 0 &&
          !/^```/.test(lines[index].trim()) && !MarkdownBlockScanner.isTableStart(lines, index) &&
          !/^#{1,6}\s/.test(lines[index]) && !/^>\s?/.test(lines[index])) {
          index++;
        }
      }

      let fragment: string = pending;
      for (let lineIndex = startLine; lineIndex < index; lineIndex++) {
        fragment += lines[lineIndex];
        if (lineIndex < lines.length - 1) {
          fragment += '\n';
        }
      }
      pending = '';
      blocks.push(MarkdownBlockScanner.makeBlock(fragment, index === lines.length));
    }

    if (pending.length > 0) {
      if (blocks.length > 0) {
        blocks[blocks.length - 1].raw += pending;
        const source: SourceSpan | null = blocks[blocks.length - 1].source;
        if (source !== null) {
          source.end = raw.length;
        }
      } else {
        blocks.push(MarkdownBlockScanner.makeBlock(pending, true));
      }
    }
    return blocks;
  }

  private static isTableStart(lines: string[], index: number): boolean {
    if (index + 1 >= lines.length || lines[index].indexOf('|') < 0 ||
      lines[index + 1].indexOf('|') < 0) {
      return false;
    }
    const cells: string[] = MarkdownBlockScanner.splitCells(lines[index + 1]);
    if (cells.length < 2) {
      return false;
    }
    for (let i = 0; i < cells.length; i++) {
      if (!/^:?-{3,}:?$/.test(cells[i])) {
        return false;
      }
    }
    return true;
  }

  private static splitCells(line: string): string[] {
    let value: string = line.trim();
    if (value.startsWith('|')) {
      value = value.substring(1);
    }
    if (value.endsWith('|')) {
      value = value.substring(0, value.length - 1);
    }
    return value.split('|').map((cell: string): string => cell.trim());
  }

  private static makeBlock(fragment: string, atEnd: boolean): ContentBlock {
    let parsed: ContentBlock[] = [];
    try {
      const html: string = MarkdownParser.toHtml(fragment);
      parsed = HtmlContentParser.parse(html, 'text', 'text/html');
    } catch (error) {
      parsed = [];
    }
    const block: ContentBlock = parsed.length > 0 ? parsed[0] :
      new ContentBlock(ContentBlockKind.RAW, fragment.trim());
    block.raw = fragment;
    block.source = new SourceSpan('markdown', 0, fragment.length);
    if (block.table !== null) {
      block.table.raw = fragment;
    }
    if (block.image !== null) {
      block.image.raw = fragment;
    }
    return block;
  }
}
