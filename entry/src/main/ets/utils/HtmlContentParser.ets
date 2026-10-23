export enum ContentBlockKind {
  PARAGRAPH = 0,
  HEADING = 1,
  QUOTE = 2,
  LIST = 3,
  CODE = 4,
  TABLE = 5,
  IMAGE = 6,
  CALLOUT = 7,
  INCLUDE = 8,
  LINK_EMBED = 9,
  PAGE_BREAK = 10,
  COLLAPSIBLE = 11,
  FOOTNOTES = 12
}

export class InlineSegment {
  text: string;
  bold: boolean;
  italic: boolean;
  code: boolean;
  href: string;
  color: string;
  backgroundColor: string;

  constructor(text: string, bold: boolean = false, italic: boolean = false,
    code: boolean = false, href: string = '', color: string = '',
    backgroundColor: string = '') {
    this.text = text;
    this.bold = bold;
    this.italic = italic;
    this.code = code;
    this.href = href;
    this.color = color;
    this.backgroundColor = backgroundColor;
  }
}

export class ImageData {
  src: string;
  alt: string;
  widthPercent: number;

  constructor(src: string, alt: string = '', widthPercent: number = 0) {
    this.src = src;
    this.alt = alt;
    this.widthPercent = widthPercent;
  }
}

export class TableCell {
  segments: InlineSegment[];
  images: ImageData[];
  header: boolean;
  colspan: number;
  rowspan: number;
  continuation: boolean;
  placeholder: boolean;

  constructor(segments: InlineSegment[], header: boolean = false,
    colspan: number = 1, rowspan: number = 1, images: ImageData[] = [],
    continuation: boolean = false, placeholder: boolean = false) {
    this.segments = segments;
    this.images = images;
    this.header = header;
    this.colspan = colspan;
    this.rowspan = rowspan;
    this.continuation = continuation;
    this.placeholder = placeholder;
  }

  text(): string {
    return HtmlContentParser.segmentsText(this.segments);
  }
}

export class TableRow {
  cells: TableCell[];
  header: boolean;

  constructor(cells: TableCell[], header: boolean = false) {
    this.cells = cells;
    this.header = header;
  }
}

export class TableData {
  rows: TableRow[];

  constructor(rows: TableRow[]) {
    this.rows = rows;
  }
}

export class CalloutData {
  type: string;
  icon: string;
  accentColor: string;
  blocks: ContentBlock[];

  constructor(type: string, icon: string, accentColor: string, blocks: ContentBlock[]) {
    this.type = type;
    this.icon = icon;
    this.accentColor = accentColor;
    this.blocks = blocks;
  }
}

export class IncludeNoteData {
  noteId: string;
  boxSize: string;
  block: string;

  constructor(noteId: string, boxSize: string = 'medium', block: string = '') {
    this.noteId = noteId;
    this.boxSize = boxSize;
    this.block = block;
  }
}

export class LinkEmbedData {
  url: string;
  title: string;
  embedType: string;

  constructor(url: string, title: string = '', embedType: string = 'opengraph') {
    this.url = url;
    this.title = title;
    this.embedType = embedType;
  }
}

export class FootnoteItem {
  index: number;
  content: string;
  backHref: string;

  constructor(index: number, content: string, backHref: string) {
    this.index = index;
    this.content = content;
    this.backHref = backHref;
  }
}

export class CollapsibleData {
  title: string;
  blocks: ContentBlock[];

  constructor(title: string, blocks: ContentBlock[]) {
    this.title = title;
    this.blocks = blocks;
  }
}

export class ContentBlock {
  kind: ContentBlockKind;
  text: string;
  level: number;
  codeLines: string[];
  language: string;
  segments: InlineSegment[];
  listItems: InlineSegment[][];
  table: TableData | null;
  image: ImageData | null;
  listMarkers: string[];
  listLevels: number[];
  indent: number;
  quoteBlocks: ContentBlock[];
  callout: CalloutData | null;
  include: IncludeNoteData | null;
  linkEmbed: LinkEmbedData | null = null;
  collapsible: CollapsibleData | null = null;
  footnotes: FootnoteItem[] = [];

  constructor(kind: ContentBlockKind, text: string = '', level: number = 0,
    codeLines: string[] = [], language: string = '', segments: InlineSegment[] = [],
    listItems: InlineSegment[][] = [], table: TableData | null = null,
    image: ImageData | null = null, listMarkers: string[] = [],
    callout: CalloutData | null = null, include: IncludeNoteData | null = null,
    listLevels: number[] = [], indent: number = 0,
    quoteBlocks: ContentBlock[] = []) {
    this.kind = kind;
    this.text = text;
    this.level = level;
    this.codeLines = codeLines;
    this.language = language;
    this.segments = segments;
    this.listItems = listItems;
    this.table = table;
    this.image = image;
    this.listMarkers = listMarkers;
    this.callout = callout;
    this.include = include;
    this.listLevels = listLevels;
    this.indent = indent;
    this.quoteBlocks = quoteBlocks;
  }
}

/**
 * HTML-to-block parser for Trilium text notes.
 *
 * It keeps the block structure ArkUI can render natively and preserves the
 * inline tags that matter for reading: code, links, bold and italic.
 *
 * Tables and images are extracted before the normal block pass so their raw
 * structure is not flattened into paragraphs.
 */
export class HtmlContentParser {
  static parse(content: string, noteType: string, mime: string): ContentBlock[] {
    if (noteType === 'code') {
      return [new ContentBlock(ContentBlockKind.CODE, '', 0,
        content.replace(/\r\n/g, '\n').split('\n'), mime.length > 0 ? mime : 'CODE')];
    }
    if (noteType !== 'text') {
      if (content.trim().length === 0) {
        return [];
      }
      return [new ContentBlock(ContentBlockKind.PARAGRAPH, content.trim(), 0, [], '',
        [new InlineSegment(content.trim())])];
    }
    if (content.trim().length === 0) {
      return [];
    }

    const hasHtml: boolean = /<[a-zA-Z][^>]*>|@@(?:P_INDENT_|LIST_LEVEL_)/.test(content);
    if (!hasHtml) {
      return HtmlContentParser.mergeLists(HtmlContentParser.parsePlainText(content));
    }

    const codeBlocks: string[] = [];
    const codeLanguages: string[] = [];
    const tables: TableData[] = [];
    const images: ImageData[] = [];
    const callouts: CalloutData[] = [];
    const quotes: ContentBlock[][] = [];
    const includes: IncludeNoteData[] = [];
    const linkEmbeds: LinkEmbedData[] = [];
    const collapsibles: CollapsibleData[] = [];
    const footnotes: FootnoteItem[] = [];
    let html: string = content.replace(/\r\n/g, '\n');
    // Trilium stores indentation as inline margin-left on paragraphs and
    // lists. Move it into a logical indent marker that ArkUI can render.
    html = html.replace(/<li([^>]*)>\s*<p(\s[^>]*)?>/gi,
      (match: string, liAttrs: string, pAttrs: string): string => {
        const pMargin: RegExpMatchArray | null =
          (pAttrs ?? '').match(/margin-left\s*:\s*(\d+)/i);
        const extra: string = pMargin !== null ? ` data-li-indent="${pMargin[1]}"` : '';
        return `<li${liAttrs}${extra}>`;
      });
    html = html.replace(/<\/p>\s*<\/li>/gi, '</li>');
    html = html.replace(/<ul([^>]*)>/gi,
      (match: string, attrs: string): string => {
        const margin: RegExpMatchArray | null =
          attrs.match(/margin-left\s*:\s*(\d+)/i);
        const extra: string = margin !== null ? ` data-ul-indent="${margin[1]}"` : '';
        return `<ul${attrs}${extra}>`;
      });
    html = html.replace(/<p(\s[^>]*)?>/gi,
      (match: string, attrs: string): string => {
        const margin: RegExpMatchArray | null =
          (attrs ?? '').match(/margin-left\s*:\s*(\d+)/i);
        const indent: string = margin !== null ? margin[1] : '0';
        return `\n\n@@P_INDENT_${indent}@@`;
      });

    html = html.replace(/<ol[^>]*class\s*=\s*["'][^"']*footnote-section[^"']*["'][^>]*>([\s\S]*?)<\/ol>/gi,
      (match: string, body: string): string => {
        const items: RegExpMatchArray | null = body.match(/<li[\s\S]*?<\/li>/gi);
        if (items !== null) {
          for (let i = 0; i < items.length; i++) {
            const li: string = items[i];
            const hrefMatch: RegExpMatchArray | null = li.match(/href\s*=\s*["'](#[^"']*)["']/i);
            let content: string = li.replace(/<span[^>]*footnote-back-link[^>]*>[\s\S]*?<\/span>/i, '');
            content = content.replace(/<div[^>]*footnote-content[^>]*>/i, '')
              .replace(/<\/div>/gi, '');
            content = HtmlContentParser.decodeEntities(
              HtmlContentParser.stripAllTags(content))
              .replace(/@@[A-Z0-9_]+@@/g, ' ')
              .replace(/\s+/g, ' ')
              .trim();
            footnotes.push(new FootnoteItem(i + 1, content,
              hrefMatch !== null ? hrefMatch[1] : ''));
          }
        }
        return footnotes.length > 0 ? '\n\n@@FOOTNOTES@@\n\n' : match;
      });

    html = html.replace(/<div[^>]*class\s*=\s*["'][^"']*page-break[^"']*["'][^>]*>[\s\S]*?<\/div>/gi,
      (): string => '\n\n@@PAGE_BREAK@@\n\n');

    html = html.replace(/<details[^>]*class\s*=\s*["'][^"']*trilium-collapsible[^"']*["'][^>]*>([\s\S]*?)<\/details>/gi,
      (match: string, body: string): string => {
        const summaryMatch: RegExpMatchArray | null =
          body.match(/<summary[^>]*>([\s\S]*?)<\/summary>/i);
        const title: string = summaryMatch !== null
          ? HtmlContentParser.decodeEntities(HtmlContentParser.stripAllTags(summaryMatch[1])).trim()
          : '可折叠内容';
        const rest: string = body.replace(/<summary[^>]*>[\s\S]*?<\/summary>/i, '');
        const blocks: ContentBlock[] = HtmlContentParser.parse(rest, 'text', 'text/html');
        collapsibles.push(new CollapsibleData(title, blocks));
        return `\n\n@@COLLAPSIBLE_${collapsibles.length - 1}@@\n\n`;
      });

    html = html.replace(/<(section|figure)([^>]*)>([\s\S]*?)<\/\1>/gi,
      (match: string, tag: string, attrs: string): string => {
        const classMatch: RegExpMatchArray | null =
          attrs.match(/class\s*=\s*("([^"]*)"|'([^']*)')/i);
        const className: string = classMatch !== null
          ? (classMatch[2] ?? classMatch[3] ?? '') : '';
        if (new RegExp('(^|\\s)link-embed(\\s|$)').test(className)) {
          const urlMatch: RegExpMatchArray | null =
            attrs.match(/data-url\s*=\s*("([^"]*)"|'([^']*)')/i);
          const titleMatch: RegExpMatchArray | null =
            attrs.match(/data-title\s*=\s*("([^"]*)"|'([^']*)')/i);
          const embedMatch: RegExpMatchArray | null =
            attrs.match(/data-embed-type\s*=\s*("([^"]*)"|'([^']*)')/i);
          if (urlMatch !== null) {
            linkEmbeds.push(new LinkEmbedData(
              HtmlContentParser.decodeEntities(urlMatch[2] ?? urlMatch[3] ?? ''),
              titleMatch !== null
                ? HtmlContentParser.decodeEntities(titleMatch[2] ?? titleMatch[3] ?? '') : '',
              embedMatch !== null ? (embedMatch[2] ?? embedMatch[3] ?? 'opengraph') : 'opengraph'
            ));
            return `\n\n@@LINK_EMBED_${linkEmbeds.length - 1}@@\n\n`;
          }
        }
        if (!new RegExp('(^|\\s)include-note(\\s|$)').test(className)) {
          return match;
        }
        const noteIdMatch: RegExpMatchArray | null =
          attrs.match(/data-note-id\s*=\s*("([^"]*)"|'([^']*)')/i);
        if (noteIdMatch === null) {
          // Attachment embeds use data-attachment-id and are not note links.
          return '';
        }
        const noteId: string = HtmlContentParser.decodeEntities(
          noteIdMatch[2] ?? noteIdMatch[3] ?? '');
        if (noteId.length === 0) {
          return '';
        }
        const boxMatch: RegExpMatchArray | null =
          attrs.match(/data-box-size\s*=\s*("([^"]*)"|'([^']*)')/i);
        const blockMatch: RegExpMatchArray | null =
          attrs.match(/data-block\s*=\s*("([^"]*)"|'([^']*)')/i);
        includes.push(new IncludeNoteData(
          noteId,
          boxMatch !== null ? (boxMatch[2] ?? boxMatch[3] ?? 'medium') : 'medium',
          blockMatch !== null ? (blockMatch[2] ?? blockMatch[3] ?? '') : ''
        ));
        return `\n\n@@INCLUDE_${includes.length - 1}@@\n\n`;
      });

    html = html.replace(/<pre[^>]*>([\s\S]*?)<\/pre>/gi,
      (match: string, body: string): string => {
        const languageMatch: RegExpMatchArray | null =
          match.match(/class\s*=\s*["'][^"']*language-([a-zA-Z0-9_-]+)/i);
        codeLanguages.push(languageMatch !== null ? languageMatch[1] : 'CODE');
        codeBlocks.push(HtmlContentParser.decodeEntities(
          HtmlContentParser.stripAllTags(body).replace(/<br\s*\/?>/gi, '\n')));
        return `\n\n@@CODE_BLOCK_${codeBlocks.length - 1}@@\n\n`;
      });

    html = html.replace(/<aside[^>]*>([\s\S]*?)<\/aside>/gi,
      (match: string, body: string): string => {
        const classMatch: RegExpMatchArray | null =
          match.match(/class\s*=\s*["']([^"']*)["']/i);
        const className: string = classMatch !== null ? classMatch[1] : '';
        if (className.indexOf('admonition') < 0) {
          return match;
        }
        const typeMatch: RegExpMatchArray | null = className.match(/admonition\s+([a-zA-Z-]+)/i);
        const type: string = typeMatch !== null ? typeMatch[1].toLowerCase() : 'note';
        const blocks: ContentBlock[] = HtmlContentParser.parse(body, 'text', 'text/html');
        callouts.push(new CalloutData(type, HtmlContentParser.calloutIcon(type),
          HtmlContentParser.calloutAccent(type), blocks));
        return `\n\n@@CALLOUT_${callouts.length - 1}@@\n\n`;
      });

    html = html.replace(/<table[^>]*>[\s\S]*?<\/table>/gi,
      (match: string): string => {
        const table: TableData | null = HtmlContentParser.parseTable(match);
        if (table === null) {
          return '';
        }
        tables.push(table);
        return `\n\n@@TABLE_${tables.length - 1}@@\n\n`;
      });

    html = html.replace(/<figure[^>]*>([\s\S]*?)<\/figure>/gi,
      (match: string, body: string): string => {
        const imageMatch: RegExpMatchArray | null = body.match(/<img[^>]*>/i);
        if (imageMatch === null) {
          return match;
        }
        const image: ImageData | null = HtmlContentParser.parseImage(imageMatch[0], body);
        if (image === null) {
          return '';
        }
        images.push(image);
        return `\n\n@@IMAGE_${images.length - 1}@@\n\n`;
      });

    html = html.replace(/<img[^>]*>/gi,
      (match: string): string => {
        const image: ImageData | null = HtmlContentParser.parseImage(match, '');
        if (image === null) {
          return '';
        }
        images.push(image);
        return `\n\n@@IMAGE_${images.length - 1}@@\n\n`;
      });

    html = html.replace(/<h([1-6])[^>]*>([\s\S]*?)<\/h\1>/gi,
      (match: string, level: string, body: string): string => {
        return `\n\n@@HEADING_${level}@@${body}\n\n`;
      });

    html = html.replace(/<blockquote[^>]*>([\s\S]*?)<\/blockquote>/gi,
      (match: string, body: string): string => {
        quotes.push(HtmlContentParser.parse(body, 'text', 'text/html'));
        return `\n\n@@QUOTE_BLOCK_${quotes.length - 1}@@\n\n`;
      });

    html = html.replace(/<input[^>]*type="checkbox"[^>]*>/gi,
      (match: string): string => {
        return match.toLowerCase().indexOf('checked') >= 0 ? '☑ ' : '☐ ';
      });
    html = html.replace(/<br\s*\/?>/gi, '\n');

    // Preserve list nesting depth before flattening list tags. The old
    // per-list regex lost nested levels, so bullets/quotes rendered flat.
    html = HtmlContentParser.markLists(html);
    html = html.replace(/<p[^>]*>/gi, '\n\n');
    html = html.replace(/<\/(p|div|ul|ol|thead|tbody|tr|td|th)>/gi, '\n\n');
    html = html.replace(/<!--[\s\S]*?-->/g, '');
    html = html.replace(/<[^>]+>/g, (match: string): string => {
      return HtmlContentParser.isInlineTag(match) ? match : '';
    });

    return HtmlContentParser.mergeLists(
      HtmlContentParser.parseMarkedText(html, codeBlocks, codeLanguages, tables, images,
        callouts, quotes, includes, linkEmbeds, collapsibles, footnotes));
  }

  private static calloutIcon(type: string): string {
    if (type === 'tip') {
      return 'bx-bulb';
    }
    if (type === 'important') {
      return 'bx-error';
    }
    if (type === 'caution' || type === 'warning') {
      return 'bx-error-circle';
    }
    return 'bx-info-circle';
  }

  private static calloutAccent(type: string): string {
    if (type === 'tip') {
      return '#40C025';
    }
    if (type === 'important') {
      return '#9839F7';
    }
    if (type === 'caution') {
      return '#FF2E2E';
    }
    if (type === 'warning') {
      return '#E2AA03';
    }
    return '#69C7FF';
  }

  private static isInlineTag(tag: string): boolean {
    return /^<\/?(a|code|strong|b|em|i|span)(\s[^>]*)?>$/i.test(tag);
  }

  private static parseMarkedText(text: string, codeBlocks: string[], codeLanguages: string[],
    tables: TableData[], images: ImageData[], callouts: CalloutData[],
    quotes: ContentBlock[][], includes: IncludeNoteData[],
    linkEmbeds: LinkEmbedData[],
    collapsibles: CollapsibleData[],
    footnotes: FootnoteItem[]): ContentBlock[] {
    const blocks: ContentBlock[] = [];
    const lines: string[] = text.split('\n');
    let paragraph: string = '';
    let pendingKind: ContentBlockKind | null = null;
    let pendingLevel: number = 0;
    let pendingMarker: string = '';

    for (let index: number = 0; index < lines.length; index++) {
      const line: string = lines[index]
        .replace(/^(&nbsp;|&#160;|\s)+/gi, '')
        .replace(/\u00A0/g, ' ')
        .trim();
      if (line.length === 0) {
        HtmlContentParser.flushParagraph(paragraph, blocks);
        paragraph = '';
        continue;
      }
      const pIndent: RegExpMatchArray | null =
        line.match(/^@@P_INDENT_(\d+)@@([\s\S]*)$/);
      if (pIndent !== null) {
        HtmlContentParser.flushParagraph(paragraph, blocks);
        const indent: number = Math.floor(Number(pIndent[1]) / 40) * 18;
        paragraph = `@@INDENT_${indent}@@${pIndent[2]}`;
        continue;
      }
      if (line === '@@LIST@@' || line === '@@QUOTE@@' ||
        (line.startsWith('@@LIST_LEVEL_') && line.endsWith('@@')) ||
        (line.startsWith('@@OLIST_') && line.endsWith('@@')) ||
        (line.startsWith('@@HEADING_') && line.endsWith('@@'))) {
        if (line === '@@LIST@@') {
          pendingKind = ContentBlockKind.LIST;
          pendingLevel = 0;
          pendingMarker = '•';
        } else if (line.startsWith('@@LIST_LEVEL_')) {
          pendingKind = ContentBlockKind.LIST;
          const end: number = line.indexOf('@@', 13);
          const meta: string = line.substring(13, end);
          const split: number = meta.indexOf('_');
          pendingLevel = split > 0 ? Number(meta.substring(0, split)) : 0;
          pendingMarker = split > 0 ? meta.substring(split + 1) : '•';
        } else if (line.startsWith('@@OLIST_')) {
          pendingKind = ContentBlockKind.LIST;
          pendingLevel = 0;
          pendingMarker = line.substring(8, line.length - 2);
        } else if (line === '@@QUOTE@@') {
          pendingKind = ContentBlockKind.QUOTE;
          pendingLevel = 0;
        } else {
          pendingKind = ContentBlockKind.HEADING;
          pendingLevel = Number(line.substring(10, line.length - 2));
        }
        continue;
      }
      if (pendingKind !== null) {
        HtmlContentParser.flushParagraph(paragraph, blocks);
        paragraph = '';
        const segments: InlineSegment[] = HtmlContentParser.parseInline(line);
        if (pendingKind === ContentBlockKind.LIST) {
          blocks.push(new ContentBlock(ContentBlockKind.LIST, HtmlContentParser.segmentsText(segments),
            0, [], '', [], [segments], null, null, [pendingMarker], null, null, [pendingLevel]));
        } else {
          blocks.push(new ContentBlock(pendingKind, HtmlContentParser.segmentsText(segments),
            pendingKind === ContentBlockKind.HEADING ? pendingLevel : 0, [], '', segments));
        }
        pendingKind = null;
        continue;
      }
      if (line.startsWith('@@CODE_BLOCK_')) {
        HtmlContentParser.flushParagraph(paragraph, blocks);
        paragraph = '';
        const end: number = line.indexOf('@@', 13);
        const codeIndex: number = Number(line.substring(13, end));
        if (!isNaN(codeIndex) && codeIndex >= 0 && codeIndex < codeBlocks.length) {
          blocks.push(new ContentBlock(ContentBlockKind.CODE, '', 0,
            codeBlocks[codeIndex].split('\n'), codeLanguages[codeIndex]));
        }
        continue;
      }
      if (line === '@@FOOTNOTES@@') {
        HtmlContentParser.flushParagraph(paragraph, blocks);
        paragraph = '';
        const block: ContentBlock = new ContentBlock(ContentBlockKind.FOOTNOTES);
        block.footnotes = footnotes.slice();
        blocks.push(block);
        continue;
      }
      if (line === '@@PAGE_BREAK@@') {
        HtmlContentParser.flushParagraph(paragraph, blocks);
        paragraph = '';
        blocks.push(new ContentBlock(ContentBlockKind.PAGE_BREAK));
        continue;
      }
      if (line.startsWith('@@COLLAPSIBLE_')) {
        HtmlContentParser.flushParagraph(paragraph, blocks);
        paragraph = '';
        const end: number = line.indexOf('@@', 14);
        const collapsibleIndex: number = Number(line.substring(14, end));
        if (!isNaN(collapsibleIndex) && collapsibleIndex >= 0 &&
          collapsibleIndex < collapsibles.length) {
          const block: ContentBlock = new ContentBlock(ContentBlockKind.COLLAPSIBLE);
          block.collapsible = collapsibles[collapsibleIndex];
          blocks.push(block);
        }
        continue;
      }
      if (line.startsWith('@@LINK_EMBED_')) {
        HtmlContentParser.flushParagraph(paragraph, blocks);
        paragraph = '';
        const end: number = line.indexOf('@@', 13);
        const embedIndex: number = Number(line.substring(13, end));
        if (!isNaN(embedIndex) && embedIndex >= 0 && embedIndex < linkEmbeds.length) {
          const block: ContentBlock = new ContentBlock(ContentBlockKind.LINK_EMBED);
          block.linkEmbed = linkEmbeds[embedIndex];
          blocks.push(block);
        }
        continue;
      }
      if (line.startsWith('@@INCLUDE_')) {
        HtmlContentParser.flushParagraph(paragraph, blocks);
        paragraph = '';
        const end: number = line.indexOf('@@', 10);
        const includeIndex: number = Number(line.substring(10, end));
        if (!isNaN(includeIndex) && includeIndex >= 0 && includeIndex < includes.length) {
          blocks.push(new ContentBlock(ContentBlockKind.INCLUDE, '', 0, [], '', [],
            [], null, null, [], null, includes[includeIndex]));
        }
        continue;
      }
      if (line.startsWith('@@TABLE_')) {
        HtmlContentParser.flushParagraph(paragraph, blocks);
        paragraph = '';
        const end: number = line.indexOf('@@', 8);
        const tableIndex: number = Number(line.substring(8, end));
        if (!isNaN(tableIndex) && tableIndex >= 0 && tableIndex < tables.length) {
          blocks.push(new ContentBlock(ContentBlockKind.TABLE, '', 0, [], '',
            [], [], tables[tableIndex]));
        }
        continue;
      }
      if (line.startsWith('@@IMAGE_')) {
        HtmlContentParser.flushParagraph(paragraph, blocks);
        paragraph = '';
        const end: number = line.indexOf('@@', 8);
        const imageIndex: number = Number(line.substring(8, end));
        if (!isNaN(imageIndex) && imageIndex >= 0 && imageIndex < images.length) {
          blocks.push(new ContentBlock(ContentBlockKind.IMAGE, '', 0, [], '',
            [], [], null, images[imageIndex]));
        }
        continue;
      }
      if (line.startsWith('@@CALLOUT_')) {
        HtmlContentParser.flushParagraph(paragraph, blocks);
        paragraph = '';
        const end: number = line.indexOf('@@', 10);
        const calloutIndex: number = Number(line.substring(10, end));
        if (!isNaN(calloutIndex) && calloutIndex >= 0 && calloutIndex < callouts.length) {
          blocks.push(new ContentBlock(ContentBlockKind.CALLOUT, '', 0, [], '',
            [], [], null, null, [], callouts[calloutIndex]));
        }
        continue;
      }
      if (line.startsWith('@@HEADING_')) {
        HtmlContentParser.flushParagraph(paragraph, blocks);
        paragraph = '';
        const levelEnd: number = line.indexOf('@@', 10);
        const level: number = Number(line.substring(10, levelEnd));
        const heading: string = line.substring(levelEnd + 2);
        if (heading.length > 0) {
          const segments: InlineSegment[] = HtmlContentParser.parseInline(heading);
          blocks.push(new ContentBlock(ContentBlockKind.HEADING,
            HtmlContentParser.segmentsText(segments), isNaN(level) ? 2 : level,
            [], '', segments));
        }
        continue;
      }
      if (line.startsWith('@@QUOTE_BLOCK_')) {
        HtmlContentParser.flushParagraph(paragraph, blocks);
        paragraph = '';
        const end: number = line.indexOf('@@', 14);
        const quoteIndex: number = Number(line.substring(14, end));
        if (!isNaN(quoteIndex) && quoteIndex >= 0 && quoteIndex < quotes.length) {
          blocks.push(new ContentBlock(ContentBlockKind.QUOTE, '', 0, [], '', [],
            [], null, null, [], null, null, [], 0, quotes[quoteIndex]));
        }
        continue;
      }
      if (line.startsWith('@@QUOTE@@')) {
        HtmlContentParser.flushParagraph(paragraph, blocks);
        paragraph = '';
        let quote: string = line.substring(9);
        let next: number = index + 1;
        while (next < lines.length) {
          const rawLine: string = lines[next].replace(/\u00A0/g, ' ');
          const nextLine: string = rawLine.trim();
          if (nextLine.length === 0 || nextLine.startsWith('@@')) {
            break;
          }
          quote += `\n${rawLine}`;
          next++;
        }
        index = next - 1;
        if (quote.length > 0) {
          const segments: InlineSegment[] = HtmlContentParser.parseInline(quote);
          blocks.push(new ContentBlock(ContentBlockKind.QUOTE,
            HtmlContentParser.segmentsText(segments), 0, [], '', segments));
        }
        continue;
      }
      if (line.startsWith('@@LIST_LEVEL_')) {
        HtmlContentParser.flushParagraph(paragraph, blocks);
        paragraph = '';
        const end: number = line.indexOf('@@', 13);
        const meta: string = line.substring(13, end);
        const split: number = meta.indexOf('_');
        const level: number = split > 0 ? Number(meta.substring(0, split)) : 0;
        const marker: string = split > 0 ? meta.substring(split + 1) : '•';
        const item: string = line.substring(end + 2)
          .replace(/^(&nbsp;|&#160;|\s)+/gi, '');
        if (item.length > 0) {
          const segments: InlineSegment[] = HtmlContentParser.parseInline(item);
          blocks.push(new ContentBlock(ContentBlockKind.LIST,
            HtmlContentParser.segmentsText(segments), 0, [], '', [], [segments],
            null, null, [marker], null, null,
            [isNaN(level) ? 0 : level]));
        }
        continue;
      }
      if (line.startsWith('@@LIST@@')) {
        HtmlContentParser.flushParagraph(paragraph, blocks);
        paragraph = '';
        const item: string = line.substring(8);
        if (item.length > 0) {
          const segments: InlineSegment[] = HtmlContentParser.parseInline(item);
          blocks.push(new ContentBlock(ContentBlockKind.LIST,
            HtmlContentParser.segmentsText(segments), 0, [], '', [], [segments],
            null, null, ['•']));
        }
        continue;
      }
      if (line.startsWith('@@OLIST_')) {
        HtmlContentParser.flushParagraph(paragraph, blocks);
        paragraph = '';
        const markerEnd: number = line.indexOf('@@', 8);
        const marker: string = line.substring(8, markerEnd);
        const item: string = line.substring(markerEnd + 2);
        if (item.length > 0) {
          const segments: InlineSegment[] = HtmlContentParser.parseInline(item);
          blocks.push(new ContentBlock(ContentBlockKind.LIST,
            HtmlContentParser.segmentsText(segments), 0, [], '', [], [segments],
            null, null, [marker]));
        }
        continue;
      }
      if (paragraph.length > 0) {
        paragraph += ' ';
      }
      paragraph += line;
    }
    HtmlContentParser.flushParagraph(paragraph, blocks);
    return blocks;
  }

  private static flushParagraph(paragraph: string, blocks: ContentBlock[]): void {
    let value: string = paragraph.trim();
    let indent: number = 0;
    const indentMatch: RegExpMatchArray | null = value.match(/^@@INDENT_(\d+)@@([\s\S]*)$/);
    if (indentMatch !== null) {
      indent = Number(indentMatch[1]);
      value = indentMatch[2].trim();
    }
    if (value.length > 0) {
      const segments: InlineSegment[] = HtmlContentParser.parseInline(value);
      blocks.push(new ContentBlock(ContentBlockKind.PARAGRAPH,
        HtmlContentParser.segmentsText(segments), 0, [], '', segments,
        [], null, null, [], null, null, [], isNaN(indent) ? 0 : indent));
    }
  }

  private static parsePlainText(content: string): ContentBlock[] {
    const raw: string = content.replace(/\r\n/g, '\n');
    const rawLines: string[] = raw.split('\n');
    let keyValueLines: number = 0;
    let indentedLines: number = 0;
    for (let lineIndex: number = 0; lineIndex < rawLines.length; lineIndex++) {
      const line: string = rawLines[lineIndex];
      if (/^\s*[\w.-]+\s*:\s*\S/.test(line)) {
        keyValueLines++;
      }
      if (/^\s{2,}\S/.test(line)) {
        indentedLines++;
      }
    }
    // A text note can contain a pasted YAML/config document. Rendering it as
    // prose collapses newlines and indentation; keep it as a code block.
    const keyValueCount: number =
      (raw.match(/[\w.-]+\s*:\s*/g) ?? []).length;
    if (keyValueLines >= 3 || (indentedLines >= 2 && rawLines.length >= 4) ||
      (keyValueCount >= 4 && rawLines.length <= 2)) {
      const language: string = raw.trimStart().startsWith('{') ? 'JSON' :
        (keyValueLines >= 3 ? 'YAML' : 'TEXT');
      return [new ContentBlock(ContentBlockKind.CODE, '', 0, rawLines, language)];
    }
    const blocks: ContentBlock[] = [];
    const paragraphs: string[] = raw.split(/\n{2,}/);
    for (let index: number = 0; index < paragraphs.length; index++) {
      const value: string = paragraphs[index].trim();
      if (value.length === 0) {
        continue;
      }
      if (value.startsWith('### ')) {
        blocks.push(HtmlContentParser.headingBlock(value.substring(4), 3));
      } else if (value.startsWith('## ')) {
        blocks.push(HtmlContentParser.headingBlock(value.substring(3), 2));
      } else if (value.startsWith('# ')) {
        blocks.push(HtmlContentParser.headingBlock(value.substring(2), 1));
      } else if (value.startsWith('> ')) {
        blocks.push(new ContentBlock(ContentBlockKind.QUOTE, value.substring(2), 0, [], '',
          [new InlineSegment(value.substring(2))]));
      } else if (value.startsWith('- ') || value.startsWith('* ')) {
        const segments: InlineSegment[] = [new InlineSegment(value.substring(2))];
        blocks.push(new ContentBlock(ContentBlockKind.LIST, value.substring(2), 0, [], '',
          [], [segments], null, null, ['•']));
      } else if (/^\d+\.\s+/.test(value)) {
        const match: RegExpMatchArray | null = value.match(/^(\d+)\.\s+/);
        const marker: string = match !== null ? `${match[1]}.` : '1.';
        const text: string = match !== null ? value.substring(match[0].length) : value;
        const segments: InlineSegment[] = [new InlineSegment(text)];
        blocks.push(new ContentBlock(ContentBlockKind.LIST, text, 0, [], '',
          [], [segments], null, null, [marker]));
      } else {
        const segments: InlineSegment[] = [new InlineSegment(value)];
        blocks.push(new ContentBlock(ContentBlockKind.PARAGRAPH, value, 0, [], '', segments));
      }
    }
    return blocks;
  }

  private static headingBlock(text: string, level: number): ContentBlock {
    const segments: InlineSegment[] = [new InlineSegment(text)];
    return new ContentBlock(ContentBlockKind.HEADING, text, level, [], '', segments);
  }

  private static markLists(html: string): string {
    const tagPattern: RegExp = /<(\/)?(ul|ol|li)([^>]*)>/gi;
    let result: string = '';
    let lastIndex: number = 0;
    let depth: number = 0;
    const counters: number[] = [];
    const indentStack: number[] = [];
    let match: RegExpExecArray | null = tagPattern.exec(html);
    while (match !== null) {
      result += html.substring(lastIndex, match.index);
      const closing: boolean = match[1] === '/';
      const tag: string = match[2].toLowerCase();
      if (tag === 'ul' || tag === 'ol') {
        if (closing) {
          depth = Math.max(0, depth - 1);
          counters.pop();
          indentStack.pop();
        } else {
          depth++;
          const margin: RegExpMatchArray | null =
            match[3].match(/data-ul-indent\s*=\s*"?(\d+)/i);
          indentStack.push(margin !== null ? Number(margin[1]) : 0);
          let start: number = 0;
          if (tag === 'ol') {
            const startMatch: RegExpMatchArray | null =
              match[3].match(/start\s*=\s*["']?(\d+)/i);
            start = startMatch !== null ? Number(startMatch[1]) : 1;
            if (isNaN(start) || start < 1) {
              start = 1;
            }
          }
          counters.push(start);
        }
      } else if (tag === 'li') {
        if (!closing) {
          let level: number = Math.max(0, depth - 1);
          const liMargin: RegExpMatchArray | null =
            match[3].match(/data-li-indent\s*=\s*"?(\d+)/i);
          const ulMargin: number = indentStack.length > 0 ? indentStack[indentStack.length - 1] : 0;
          const liMarginValue: number = liMargin !== null ? Number(liMargin[1]) : 0;
          const cssLevel: number = Math.floor(Math.max(ulMargin, liMarginValue) / 40);
          level = Math.max(level, cssLevel);
          let marker: string = '•';
          if (depth > 0 && counters.length >= depth && counters[depth - 1] > 0) {
            marker = `${counters[depth - 1]}.`;
            counters[depth - 1]++;
          }
          result += `\n@@LIST_LEVEL_${level}_${marker}@@\n`;
        } else {
          result += '\n';
        }
      }
      lastIndex = tagPattern.lastIndex;
      match = tagPattern.exec(html);
    }
    return result + html.substring(lastIndex);
  }

  private static mergeLists(blocks: ContentBlock[]): ContentBlock[] {
    const merged: ContentBlock[] = [];
    for (let index: number = 0; index < blocks.length; index++) {
      const block: ContentBlock = blocks[index];
      if (block.kind === ContentBlockKind.LIST && merged.length > 0 &&
        merged[merged.length - 1].kind === ContentBlockKind.LIST) {
        const last: ContentBlock = merged[merged.length - 1];
        for (let itemIndex: number = 0; itemIndex < block.listItems.length; itemIndex++) {
          last.listItems.push(block.listItems[itemIndex]);
        }
        for (let markerIndex: number = 0; markerIndex < block.listMarkers.length; markerIndex++) {
          last.listMarkers.push(block.listMarkers[markerIndex]);
        }
        for (let levelIndex: number = 0; levelIndex < block.listLevels.length; levelIndex++) {
          last.listLevels.push(block.listLevels[levelIndex]);
        }
        last.text = last.listItems.map((item: InlineSegment[]) =>
          HtmlContentParser.segmentsText(item)).join('\n');
      } else {
        merged.push(block);
      }
    }
    return merged;
  }

  private static parseTable(raw: string): TableData | null {
    const rows: TableRow[] = [];
    const rowPattern: RegExp = /<tr[^>]*>([\s\S]*?)<\/tr>/gi;
    let rowMatch: RegExpExecArray | null = rowPattern.exec(raw);
    while (rowMatch !== null) {
      const cells: TableCell[] = [];
      const cellPattern: RegExp = /<(th|td)([^>]*)>([\s\S]*?)<\/\1>/gi;
      let cellMatch: RegExpExecArray | null = cellPattern.exec(rowMatch[1]);
      while (cellMatch !== null) {
        const tag: string = cellMatch[1].toLowerCase();
        const attrs: string = cellMatch[2];
        const images: ImageData[] = [];
        const cellBody: string = cellMatch[3].replace(/<img[^>]*>/gi,
          (imageTag: string): string => {
            const image: ImageData | null = HtmlContentParser.parseImage(imageTag, '');
            if (image !== null) {
              images.push(image);
            }
            return '';
          });
        const segments: InlineSegment[] = HtmlContentParser.parseInline(cellBody);
        cells.push(new TableCell(segments, tag === 'th',
          HtmlContentParser.readSpan(attrs, 'colspan'),
          HtmlContentParser.readSpan(attrs, 'rowspan'), images));
        cellMatch = cellPattern.exec(rowMatch[1]);
      }
      if (cells.length > 0) {
        let isHeader: boolean = true;
        for (let index: number = 0; index < cells.length; index++) {
          if (!cells[index].header) {
            isHeader = false;
            break;
          }
        }
        rows.push(new TableRow(cells, isHeader));
      }
      rowMatch = rowPattern.exec(raw);
    }
    if (rows.length > 0) {
      HtmlContentParser.repeatRowspans(rows);
    }
    return rows.length > 0 ? new TableData(rows) : null;
  }

  /**
   * rowspan is intentionally degraded: the merged cell content is repeated in
   * the following rows at the same column and drawn with the continuation
   * style. This keeps the grid aligned without measuring a native cell span.
   */
  private static repeatRowspans(rows: TableRow[]): void {
    for (let rowIndex: number = 0; rowIndex < rows.length; rowIndex++) {
      const row: TableRow = rows[rowIndex];
      for (let cellIndex: number = 0; cellIndex < row.cells.length; cellIndex++) {
        const cell: TableCell = row.cells[cellIndex];
        if (cell.rowspan <= 1) {
          continue;
        }
        for (let offset: number = 1; offset < cell.rowspan; offset++) {
          const targetIndex: number = rowIndex + offset;
          if (targetIndex >= rows.length) {
            break;
          }
          const target: TableRow = rows[targetIndex];
          const copy: TableCell = new TableCell(cell.segments, cell.header,
            cell.colspan, 1, cell.images, true, false);
          target.cells.splice(Math.min(cellIndex, target.cells.length), 0, copy);
        }
      }
    }

    let maxColumns: number = 0;
    for (let rowIndex: number = 0; rowIndex < rows.length; rowIndex++) {
      let columns: number = 0;
      for (let cellIndex: number = 0; cellIndex < rows[rowIndex].cells.length; cellIndex++) {
        columns += Math.max(1, rows[rowIndex].cells[cellIndex].colspan);
      }
      maxColumns = Math.max(maxColumns, columns);
    }
    for (let rowIndex: number = 0; rowIndex < rows.length; rowIndex++) {
      let columns: number = 0;
      for (let cellIndex: number = 0; cellIndex < rows[rowIndex].cells.length; cellIndex++) {
        columns += Math.max(1, rows[rowIndex].cells[cellIndex].colspan);
      }
      while (columns < maxColumns) {
        rows[rowIndex].cells.push(new TableCell([], false, 1, 1, [], true, true));
        columns++;
      }
    }
  }

  private static readSpan(attrs: string, name: string): number {
    const pattern: RegExp = new RegExp(`${name}\\s*=\\s*["']?(\\d+)`, 'i');
    const match: RegExpMatchArray | null = attrs.match(pattern);
    if (match === null) {
      return 1;
    }
    const value: number = Number(match[1]);
    return isNaN(value) || value < 1 ? 1 : value;
  }

  private static parseImage(tag: string, figureBody: string): ImageData | null {
    const srcMatch: RegExpMatchArray | null =
      tag.match(/src\s*=\s*("([^"]*)"|'([^']*)'|([^\s>]+))/i);
    if (srcMatch === null) {
      return null;
    }
    const src: string = srcMatch[2] !== undefined ? srcMatch[2] :
      (srcMatch[3] !== undefined ? srcMatch[3] : srcMatch[4]);
    if (src === undefined || src.length === 0) {
      return null;
    }
    let alt: string = '';
    const altMatch: RegExpMatchArray | null =
      tag.match(/alt\s*=\s*("([^"]*)"|'([^']*)')/i);
    if (altMatch !== null) {
      alt = altMatch[2] !== undefined ? altMatch[2] : (altMatch[3] ?? '');
    }
    if (alt.length === 0 && figureBody.length > 0) {
      const captionMatch: RegExpMatchArray | null =
        figureBody.match(/<figcaption[^>]*>([\s\S]*?)<\/figcaption>/i);
      if (captionMatch !== null) {
        alt = HtmlContentParser.stripAllTags(captionMatch[1]).trim();
      }
    }
    const widthMatch: RegExpMatchArray | null =
      tag.match(/width\s*=\s*"(\d+)%"/i);
    let widthPercent: number = widthMatch !== null ? Number(widthMatch[1]) : 0;
    if (widthPercent === 0) {
      const styleMatch: RegExpMatchArray | null =
        tag.match(/style\s*=\s*"([^"]*)"/i);
      if (styleMatch !== null) {
        const styleWidth: RegExpMatchArray | null =
          styleMatch[1].match(/width\s*:\s*(\d+(?:\.\d+)?)%/i);
        if (styleWidth !== null) {
          widthPercent = Number(styleWidth[1]);
        }
      }
    }
    return new ImageData(HtmlContentParser.decodeEntities(src), HtmlContentParser.decodeEntities(alt),
      isNaN(widthPercent) ? 0 : widthPercent);
  }

  static parseInline(html: string): InlineSegment[] {
    const segments: InlineSegment[] = [];
    const tagPattern: RegExp = /<(\/?)(strong|b|em|i|code|a|span)(\s[^>]*)?>/gi;
    let boldDepth: number = 0;
    let italicDepth: number = 0;
    let codeDepth: number = 0;
    let href: string = '';
    let color: string = '';
    let backgroundColor: string = '';
    const colorStack: string[] = [];
    const backgroundStack: string[] = [];
    let lastIndex: number = 0;
    let match: RegExpExecArray | null = tagPattern.exec(html);
    while (match !== null) {
      HtmlContentParser.pushInline(segments, html.substring(lastIndex, match.index),
        boldDepth > 0, italicDepth > 0, codeDepth > 0, href, color, backgroundColor);
      const closing: boolean = match[1] === '/';
      const tag: string = match[2].toLowerCase();
      const attrs: string = match[3] ?? '';
      if (tag === 'strong' || tag === 'b') {
        boldDepth += closing ? -1 : 1;
      } else if (tag === 'em' || tag === 'i') {
        italicDepth += closing ? -1 : 1;
      } else if (tag === 'code') {
        codeDepth += closing ? -1 : 1;
      } else if (tag === 'a') {
        if (closing) {
          href = '';
        } else {
          const hrefMatch: RegExpMatchArray | null =
            attrs.match(/href\s*=\s*("([^"]*)"|'([^']*)'|([^\s>]+))/i);
          const rawHref: string = hrefMatch !== null
            ? (hrefMatch[2] ?? hrefMatch[3] ?? hrefMatch[4] ?? '') : '';
          href = HtmlContentParser.decodeEntities(rawHref);
        }
      } else if (tag === 'span') {
        if (closing) {
          color = colorStack.length > 0 ? colorStack.pop() ?? '' : '';
          backgroundColor = backgroundStack.length > 0 ? backgroundStack.pop() ?? '' : '';
        } else {
          colorStack.push(color);
          backgroundStack.push(backgroundColor);
          const style: string = HtmlContentParser.styleAttribute(attrs);
          const parsedColor: string = HtmlContentParser.normalizeCssColor(
            HtmlContentParser.styleValue(style, 'color'));
          if (parsedColor.length > 0) {
            color = parsedColor;
          }
          const parsedBackground: string = HtmlContentParser.normalizeCssColor(
            HtmlContentParser.styleValue(style, 'background-color'));
          if (parsedBackground.length > 0) {
            backgroundColor = parsedBackground;
          }
        }
      }
      boldDepth = Math.max(0, boldDepth);
      italicDepth = Math.max(0, italicDepth);
      codeDepth = Math.max(0, codeDepth);
      lastIndex = tagPattern.lastIndex;
      match = tagPattern.exec(html);
    }
    HtmlContentParser.pushInline(segments, html.substring(lastIndex),
      boldDepth > 0, italicDepth > 0, codeDepth > 0, href, color, backgroundColor);
    return HtmlContentParser.mergeInline(segments);
  }

  private static styleAttribute(attrs: string): string {
    const styleMatch: RegExpMatchArray | null =
      attrs.match(/style\s*=\s*("([^"]*)"|'([^']*)')/i);
    if (styleMatch === null) {
      return '';
    }
    return styleMatch[2] ?? styleMatch[3] ?? '';
  }

  private static styleValue(style: string, property: string): string {
    if (style.length === 0) {
      return '';
    }
    const pattern: RegExp = new RegExp(`(?:^|;)\\s*${property}\\s*:\\s*([^;]+)`, 'i');
    const match: RegExpMatchArray | null = style.match(pattern);
    return match !== null ? match[1].trim() : '';
  }

  private static normalizeCssColor(value: string): string {
    const color: string = value.trim();
    if (color.length === 0) {
      return '';
    }
    if (color.startsWith('#')) {
      return color;
    }
    const rgbMatch: RegExpMatchArray | null = color.match(
      /^rgba?\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)(?:\s*,\s*([0-9.]+))?\s*\)$/i);
    if (rgbMatch !== null) {
      const red: number = Math.max(0, Math.min(255, Math.round(Number(rgbMatch[1]))));
      const green: number = Math.max(0, Math.min(255, Math.round(Number(rgbMatch[2]))));
      const blue: number = Math.max(0, Math.min(255, Math.round(Number(rgbMatch[3]))));
      if (rgbMatch[4] !== undefined) {
        const alpha: number = Math.max(0, Math.min(255, Math.round(Number(rgbMatch[4]) * 255)));
        return `#${HtmlContentParser.hex2(alpha)}${HtmlContentParser.hex2(red)}${HtmlContentParser.hex2(green)}${HtmlContentParser.hex2(blue)}`;
      }
      return `#${HtmlContentParser.hex2(red)}${HtmlContentParser.hex2(green)}${HtmlContentParser.hex2(blue)}`;
    }
    const hslMatch: RegExpMatchArray | null = color.match(
      /^hsla?\(\s*([0-9.]+)\s*,\s*([0-9.]+)%\s*,\s*([0-9.]+)%(?:\s*,\s*([0-9.]+))?\s*\)$/i);
    if (hslMatch !== null) {
      const rgba: number[] = HtmlContentParser.hslToRgb(Number(hslMatch[1]),
        Number(hslMatch[2]), Number(hslMatch[3]));
      if (hslMatch[4] !== undefined) {
        const alpha: number = Math.max(0, Math.min(255, Math.round(Number(hslMatch[4]) * 255)));
        return `#${HtmlContentParser.hex2(alpha)}${HtmlContentParser.hex2(rgba[0])}${HtmlContentParser.hex2(rgba[1])}${HtmlContentParser.hex2(rgba[2])}`;
      }
      return `#${HtmlContentParser.hex2(rgba[0])}${HtmlContentParser.hex2(rgba[1])}${HtmlContentParser.hex2(rgba[2])}`;
    }
    return color;
  }

  private static hslToRgb(hue: number, saturation: number, lightness: number): number[] {
    const h: number = ((hue % 360) + 360) % 360 / 360;
    const s: number = saturation / 100;
    const l: number = lightness / 100;
    if (s === 0) {
      const value: number = Math.round(l * 255);
      return [value, value, value];
    }
    const q: number = l < 0.5 ? l * (1 + s) : l + s - l * s;
    const p: number = 2 * l - q;
    const red: number = Math.round(HtmlContentParser.hueToRgb(p, q, h + 1 / 3) * 255);
    const green: number = Math.round(HtmlContentParser.hueToRgb(p, q, h) * 255);
    const blue: number = Math.round(HtmlContentParser.hueToRgb(p, q, h - 1 / 3) * 255);
    return [red, green, blue];
  }

  private static hueToRgb(p: number, q: number, t: number): number {
    let value: number = t;
    if (value < 0) {
      value += 1;
    }
    if (value > 1) {
      value -= 1;
    }
    if (value < 1 / 6) {
      return p + (q - p) * 6 * value;
    }
    if (value < 1 / 2) {
      return q;
    }
    if (value < 2 / 3) {
      return p + (q - p) * (2 / 3 - value) * 6;
    }
    return p;
  }

  private static hex2(value: number): string {
    const result: string = Math.max(0, Math.min(255, value)).toString(16).toUpperCase();
    return result.length === 1 ? `0${result}` : result;
  }

  private static pushInline(segments: InlineSegment[], raw: string, bold: boolean,
    italic: boolean, code: boolean, href: string, color: string, backgroundColor: string): void {
    if (raw.length === 0) {
      return;
    }
    let text: string = HtmlContentParser.stripAllTags(raw);
    text = HtmlContentParser.decodeEntities(text);
    text = text.replace(/\r/g, '');
    text = HtmlContentParser.stripInternalMarkers(text);
    if (!code) {
      text = text.replace(/[ \t\f\v]+/g, ' ');
    } else {
      text = text.replace(/ /g, '\u00A0');
    }
    if (text.length === 0) {
      return;
    }
    segments.push(new InlineSegment(text, bold, italic, code, href, color, backgroundColor));
  }

  private static stripInternalMarkers(text: string): string {
    return text.replace(
      /@@(?:HEADING_\d+|LIST|OLIST_[0-9.]+|QUOTE|CODE_BLOCK_\d+|TABLE_\d+|IMAGE_\d+|CALLOUT_\d+|INCLUDE_\d+)@@/g,
      '');
  }

  private static mergeInline(segments: InlineSegment[]): InlineSegment[] {
    const merged: InlineSegment[] = [];
    for (let index: number = 0; index < segments.length; index++) {
      const segment: InlineSegment = segments[index];
      if (merged.length > 0) {
        const last: InlineSegment = merged[merged.length - 1];
        if (last.bold === segment.bold && last.italic === segment.italic &&
          last.code === segment.code && last.href === segment.href &&
          last.color === segment.color && last.backgroundColor === segment.backgroundColor) {
          last.text += segment.text;
          continue;
        }
      }
      merged.push(segment);
    }
    if (merged.length > 0) {
      merged[0].text = merged[0].text.replace(/^\s+/, '');
      merged[merged.length - 1].text =
        merged[merged.length - 1].text.replace(/\s+$/, '');
    }
    return merged.filter((segment: InlineSegment) => segment.text.length > 0);
  }

  private static stripAllTags(value: string): string {
    return value.replace(/<[^>]+>/g, '');
  }

  private static decodeEntities(value: string): string {
    let result: string = value
      .replace(/&nbsp;/gi, ' ')
      .replace(/&amp;/gi, '&')
      .replace(/&lt;/gi, '<')
      .replace(/&gt;/gi, '>')
      .replace(/&quot;/gi, '"')
      .replace(/&#39;/gi, '\'');
    result = result.replace(/&#(\d+);/g, (match: string, code: string): string => {
      return String.fromCharCode(Number(code));
    });
    return result;
  }

  static segmentsText(segments: InlineSegment[]): string {
    let text: string = '';
    for (let index: number = 0; index < segments.length; index++) {
      text += segments[index].text;
    }
    return text;
  }

  static plainText(blocks: ContentBlock[]): string {
    let text: string = '';
    for (let index: number = 0; index < blocks.length; index++) {
      const block: ContentBlock = blocks[index];
      if (block.kind === ContentBlockKind.CODE) {
        text += block.codeLines.join('\n');
      } else if (block.kind === ContentBlockKind.LIST) {
        for (let itemIndex: number = 0; itemIndex < block.listItems.length; itemIndex++) {
          text += HtmlContentParser.segmentsText(block.listItems[itemIndex]);
          text += '\n';
        }
      } else if (block.kind === ContentBlockKind.TABLE) {
        if (block.table !== null) {
          for (let rowIndex: number = 0; rowIndex < block.table.rows.length; rowIndex++) {
            const row: TableRow = block.table.rows[rowIndex];
            for (let cellIndex: number = 0; cellIndex < row.cells.length; cellIndex++) {
              text += `${row.cells[cellIndex].text()}\n`;
            }
          }
        }
      } else if (block.kind === ContentBlockKind.CALLOUT) {
        if (block.callout !== null) {
          text += HtmlContentParser.plainText(block.callout.blocks);
        }
      } else if (block.kind === ContentBlockKind.INCLUDE) {
        text += '引用笔记';
      } else if (block.kind !== ContentBlockKind.IMAGE) {
        text += HtmlContentParser.segmentsText(block.segments);
      }
      text += '\n';
    }
    return text;
  }
}
