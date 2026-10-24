import {
  ContentBlock,
  ContentBlockKind,
  HtmlContentParser,
  SourceSpan
} from '../HtmlContentParser';

/**
 * Splits an HTML note body into top-level blocks without normalising it.
 *
 * Every block keeps the exact source fragment it came from. That raw fragment
 * is what makes a parse -> serialize round trip byte-identical while a block is
 * untouched. Semantic fields are filled by the existing HtmlContentParser so
 * the current renderer keeps working during the migration.
 */
export class HtmlBlockScanner {
  private static readonly BLOCK_TAGS: string[] = [
    'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'li', 'pre',
    'blockquote', 'table', 'figure', 'hr', 'div', 'section', 'article',
    'img', 'details', 'aside'
  ];

  static scan(raw: string): ContentBlock[] {
    if (raw.length === 0) {
      return [];
    }
    const blocks: ContentBlock[] = [];
    let index: number = 0;
    let prefix: string = '';

    while (index < raw.length) {
      if (raw.charAt(index) !== '<') {
        const next: number = raw.indexOf('<', index);
        const end: number = next < 0 ? raw.length : next;
        const text: string = raw.substring(index, end);
        if (text.trim().length === 0) {
          prefix += text;
        } else {
          blocks.push(HtmlBlockScanner.makeTextBlock(prefix + text, index - prefix.length, end));
          prefix = '';
        }
        index = end;
        continue;
      }

      if (raw.startsWith('<!--', index)) {
        const close: number = raw.indexOf('-->', index + 4);
        const end: number = close < 0 ? raw.length : close + 3;
        blocks.push(HtmlBlockScanner.makeRawBlock(raw.substring(index, end), index, end));
        index = end;
        continue;
      }

      if (raw.startsWith('<!', index)) {
        const end: number = HtmlBlockScanner.findTagEnd(raw, index);
        blocks.push(HtmlBlockScanner.makeRawBlock(raw.substring(index, end), index, end));
        index = end;
        continue;
      }

      if (raw.startsWith('</', index)) {
        const end: number = HtmlBlockScanner.findTagEnd(raw, index);
        prefix += raw.substring(index, end);
        index = end;
        continue;
      }

      const tagMatch: RegExpMatchArray | null =
        raw.substring(index).match(/^<([A-Za-z][A-Za-z0-9:_-]*)/);
      if (tagMatch === null) {
        prefix += raw.charAt(index);
        index++;
        continue;
      }

      const tag: string = tagMatch[1].toLowerCase();
      const openEnd: number = HtmlBlockScanner.findTagEnd(raw, index);
      const openTag: string = raw.substring(index, openEnd);
      const selfClosing: boolean = /\/\s*>$/.test(openTag) ||
        HtmlBlockScanner.isVoidTag(tag);
      let end: number = openEnd;
      if (!selfClosing) {
        end = HtmlBlockScanner.findElementEnd(raw, index, tag);
      }

      const fragment: string = prefix + raw.substring(index, end);
      const start: number = index - prefix.length;
      prefix = '';
      blocks.push(HtmlBlockScanner.makeBlock(fragment, tag, start, end));
      index = end;
    }

    if (prefix.length > 0) {
      if (blocks.length > 0) {
        blocks[blocks.length - 1].raw += prefix;
        const source: SourceSpan | null = blocks[blocks.length - 1].source;
        if (source !== null) {
          source.end = raw.length;
        }
      } else {
        blocks.push(HtmlBlockScanner.makeTextBlock(prefix, 0, raw.length));
      }
    }
    return blocks;
  }

  private static makeBlock(fragment: string, tag: string, start: number, end: number): ContentBlock {
    if (HtmlBlockScanner.BLOCK_TAGS.indexOf(tag) < 0) {
      return HtmlBlockScanner.makeRawBlock(fragment, start, end);
    }
    let parsed: ContentBlock[] = [];
    try {
      parsed = HtmlContentParser.parse(fragment, 'text', 'text/html');
    } catch (error) {
      parsed = [];
    }
    if (parsed.length === 0) {
      return HtmlBlockScanner.makeRawBlock(fragment, start, end);
    }
    const block: ContentBlock = parsed[0];
    block.raw = fragment;
    block.source = new SourceSpan('html', start, end);
    block.id = '';
    if (block.table !== null) {
      block.table.raw = fragment;
    }
    if (block.image !== null) {
      block.image.raw = fragment;
    }
    return block;
  }

  private static makeRawBlock(fragment: string, start: number, end: number): ContentBlock {
    const block: ContentBlock = new ContentBlock(ContentBlockKind.RAW, fragment.trim());
    block.raw = fragment;
    block.source = new SourceSpan('html', start, end);
    return block;
  }

  private static makeTextBlock(fragment: string, start: number, end: number): ContentBlock {
    const block: ContentBlock = new ContentBlock(ContentBlockKind.PARAGRAPH, fragment.trim());
    block.raw = fragment;
    block.source = new SourceSpan('html', start, end);
    return block;
  }

  private static isVoidTag(tag: string): boolean {
    return tag === 'img' || tag === 'hr' || tag === 'br' || tag === 'input' ||
      tag === 'meta' || tag === 'link' || tag === 'source';
  }

  private static findTagEnd(raw: string, start: number): number {
    let quote: string = '';
    for (let i = start; i < raw.length; i++) {
      const ch: string = raw.charAt(i);
      if (quote.length > 0) {
        if (ch === quote) {
          quote = '';
        }
      } else if (ch === '"' || ch === '\'') {
        quote = ch;
      } else if (ch === '>') {
        return i + 1;
      }
    }
    return raw.length;
  }

  private static findElementEnd(raw: string, start: number, tag: string): number {
    const escaped: string = tag.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const pattern: RegExp = new RegExp(`<(/?)${escaped}(\\s[^>]*)?>`, 'gi');
    pattern.lastIndex = start;
    let depth: number = 0;
    let match: RegExpExecArray | null = pattern.exec(raw);
    while (match !== null) {
      const closing: boolean = match[1] === '/';
      const full: string = match[0];
      const selfClosing: boolean = /\/\s*>$/.test(full);
      if (closing) {
        depth--;
        if (depth <= 0) {
          return match.index + full.length;
        }
      } else if (!selfClosing) {
        depth++;
      }
      match = pattern.exec(raw);
    }
    return raw.length;
  }
}
