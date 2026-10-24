import {
  ContentBlock,
  ContentBlockKind,
  InlineSegment
} from '../HtmlContentParser';
import { HtmlBlockScanner } from './HtmlBlockScanner';
import { MarkdownBlockScanner } from './MarkdownBlockScanner';

/**
 * Bidirectional codec facade for the block model.
 *
 * The contract for the first migration step is intentionally conservative:
 * - an unmodified block always serializes from its original `raw` fragment;
 * - only blocks marked `dirty` take the generated serialization path;
 * - tables/images fall back to their original raw fragment until their
 *   dedicated editors are wired in.
 */
export class TriliumCodec {
  static parseToModel(rawText: string, format: string): ContentBlock[] {
    const blocks: ContentBlock[] = format === 'markdown'
      ? MarkdownBlockScanner.scan(rawText)
      : HtmlBlockScanner.scan(rawText);
    TriliumCodec.assignIds(blocks, 'b');
    return blocks;
  }

  static serializeToRaw(blocks: ContentBlock[], format: string,
    preserveUntouched: boolean = true): string {
    let output: string = '';
    for (let i = 0; i < blocks.length; i++) {
      const block: ContentBlock = blocks[i];
      if (preserveUntouched && !block.dirty && block.raw.length > 0) {
        output += block.raw;
      } else {
        output += TriliumCodec.serializeBlock(block, format);
      }
    }
    return output;
  }

  static parseBlock(rawText: string, format: string): ContentBlock {
    const blocks: ContentBlock[] = TriliumCodec.parseToModel(rawText, format);
    if (blocks.length > 0) {
      return blocks[0];
    }
    const block: ContentBlock = new ContentBlock(ContentBlockKind.RAW, rawText);
    block.raw = rawText;
    return block;
  }

  static serializeBlock(block: ContentBlock, format: string): string {
    if (block.serializeMode === 'raw' && block.raw.length > 0) {
      return block.raw;
    }
    if (!block.dirty && block.raw.length > 0) {
      return block.raw;
    }
    return format === 'markdown' ?
      TriliumCodec.serializeMarkdownBlock(block) :
      TriliumCodec.serializeHtmlBlock(block);
  }

  static replaceBlock(blocks: ContentBlock[], blockId: string,
    replacement: ContentBlock): ContentBlock[] {
    for (let i = 0; i < blocks.length; i++) {
      if (blocks[i].id === blockId) {
        replacement.id = blockId;
        replacement.dirty = true;
        blocks[i] = replacement;
        return blocks;
      }
    }
    return blocks;
  }

  private static assignIds(blocks: ContentBlock[], prefix: string): void {
    for (let i = 0; i < blocks.length; i++) {
      const block: ContentBlock = blocks[i];
      block.id = `${prefix}${i + 1}`;
      if (block.children.length > 0) {
        TriliumCodec.assignIds(block.children, `${block.id}-`);
      }
      if (block.quoteBlocks.length > 0) {
        TriliumCodec.assignIds(block.quoteBlocks, `${block.id}-q`);
      }
      const callout = block.callout;
      if (callout !== null) {
        TriliumCodec.assignIds(callout.blocks, `${block.id}-c`);
      }
      const collapsible = block.collapsible;
      if (collapsible !== null) {
        TriliumCodec.assignIds(collapsible.blocks, `${block.id}-k`);
      }
    }
  }

  private static serializeInlineHtml(segments: InlineSegment[]): string {
    let html: string = '';
    for (let i = 0; i < segments.length; i++) {
      let text: string = TriliumCodec.escapeHtml(segments[i].text);
      if (segments[i].code) {
        text = `<code>${text}</code>`;
      }
      if (segments[i].bold) {
        text = `<strong>${text}</strong>`;
      }
      if (segments[i].italic) {
        text = `<em>${text}</em>`;
      }
      if (segments[i].href.length > 0) {
        text = `<a href="${TriliumCodec.escapeHtml(segments[i].href)}">${text}</a>`;
      }
      html += text;
    }
    return html;
  }

  private static serializeHtmlBlock(block: ContentBlock): string {
    if (block.raw.length > 0 && block.kind === ContentBlockKind.RAW) {
      return block.raw;
    }
    if (block.raw.length > 0 && block.kind === ContentBlockKind.TABLE &&
      block.serializeMode !== 'model') {
      return block.raw;
    }
    switch (block.kind) {
      case ContentBlockKind.HEADING:
        return `<h${Math.max(1, Math.min(6, block.level))}>` +
          `${TriliumCodec.serializeInlineHtml(block.segments)}</h${block.level}>`;
      case ContentBlockKind.CODE:
        return `<pre><code class="language-${TriliumCodec.escapeHtml(block.language)}">` +
          `${TriliumCodec.escapeHtml(block.codeLines.join('\n'))}</code></pre>`;
      case ContentBlockKind.PARAGRAPH:
        return `<p>${TriliumCodec.serializeInlineHtml(block.segments)}</p>`;
      case ContentBlockKind.LIST:
        return TriliumCodec.serializeHtmlList(block);
      case ContentBlockKind.TABLE:
        return TriliumCodec.serializeHtmlTable(block);
      case ContentBlockKind.IMAGE:
        return TriliumCodec.serializeHtmlImage(block);
      case ContentBlockKind.CALLOUT:
        return TriliumCodec.serializeHtmlCallout(block);
      default:
        return block.raw.length > 0 ? block.raw : block.text;
    }
  }

  private static serializeHtmlCallout(block: ContentBlock): string {
    if (block.callout === null) {
      return block.raw;
    }
    const callout = block.callout;
    let content: string = '';
    for (let i = 0; i < callout.blocks.length; i++) {
      content += TriliumCodec.serializeBlock(callout.blocks[i], 'html');
    }
    const title: string = callout.title.length > 0 ?
      `<div class="admonition-title">${TriliumCodec.escapeHtml(callout.title)}</div>` : '';
    return `<aside class="admonition ${TriliumCodec.escapeHtml(callout.type)}" ` +
      `data-callout-type="${TriliumCodec.escapeHtml(callout.type)}">` +
      `${title}<div class="callout-content">${content}</div></aside>`;
  }

  private static serializeHtmlTable(block: ContentBlock): string {
    if (block.table === null) {
      return block.raw;
    }
    let html: string = '<table>';
    if (block.table.caption.length > 0) {
      html += `<caption>${TriliumCodec.escapeHtml(block.table.caption)}</caption>`;
    }
    for (let r = 0; r < block.table.rows.length; r++) {
      const row = block.table.rows[r];
      html += '<tr>';
      for (let c = 0; c < row.cells.length; c++) {
        const cell = row.cells[c];
        if (cell.continuation) {
          continue;
        }
        const tag: string = cell.header ? 'th' : 'td';
        let attrs: string = '';
        if (cell.colspan > 1) {
          attrs += ` colspan="${cell.colspan}"`;
        }
        if (cell.rowspan > 1) {
          attrs += ` rowspan="${cell.rowspan}"`;
        }
        if (cell.align.length > 0) {
          attrs += ` style="text-align:${TriliumCodec.escapeHtml(cell.align)}"`;
        }
        let content: string = TriliumCodec.serializeInlineHtml(cell.segments);
        for (let i = 0; i < cell.images.length; i++) {
          const image = cell.images[i];
          content += `<img src="${TriliumCodec.escapeHtml(image.src)}" ` +
            `alt="${TriliumCodec.escapeHtml(image.alt)}">`;
        }
        html += `<${tag}${attrs}>${content}</${tag}>`;
      }
      html += '</tr>';
    }
    html += '</table>';
    return html;
  }

  private static serializeHtmlImage(block: ContentBlock): string {
    if (block.image === null) {
      return block.raw;
    }
    const image = block.image;
    let attrs: string = '';
    if (image.width > 0) {
      attrs += ` width="${image.width}"`;
    }
    if (image.height > 0) {
      attrs += ` height="${image.height}"`;
    }
    if (image.widthPercent > 0) {
      attrs += ` style="width:${image.widthPercent}%"`;
    }
    const title: string = image.title.length > 0 ?
      ` title="${TriliumCodec.escapeHtml(image.title)}"` : '';
    let html: string = `<img src="${TriliumCodec.escapeHtml(image.src)}" ` +
      `alt="${TriliumCodec.escapeHtml(image.alt)}"${title}${attrs}>`;
    if (image.href.length > 0) {
      html = `<a href="${TriliumCodec.escapeHtml(image.href)}">${html}</a>`;
    }
    if (image.figureCaption.length > 0) {
      html = `<figure>${html}<figcaption>` +
        `${TriliumCodec.escapeHtml(image.figureCaption)}</figcaption></figure>`;
    }
    return html;
  }

  private static serializeHtmlList(block: ContentBlock): string {
    let ordered: boolean = false;
    for (let i = 0; i < block.listMarkers.length; i++) {
      if (/^\d+[.)]$/.test(block.listMarkers[i])) {
        ordered = true;
        break;
      }
    }
    let html: string = ordered ? '<ol>' : '<ul>';
    let level: number = 0;
    for (let i = 0; i < block.listItems.length; i++) {
      const targetLevel: number = i < block.listLevels.length ? block.listLevels[i] : 0;
      while (targetLevel > level) {
        html += ordered ? '<ol>' : '<ul>';
        level++;
      }
      while (targetLevel < level) {
        html += ordered ? '</ol>' : '</ul>';
        level--;
      }
      html += `<li>${TriliumCodec.serializeInlineHtml(block.listItems[i])}</li>`;
    }
    while (level > 0) {
      html += ordered ? '</ol>' : '</ul>';
      level--;
    }
    html += ordered ? '</ol>' : '</ul>';
    return html;
  }

  private static serializeMarkdownBlock(block: ContentBlock): string {
    if (block.raw.length > 0 &&
      (block.kind === ContentBlockKind.TABLE || block.kind === ContentBlockKind.IMAGE ||
        block.kind === ContentBlockKind.RAW)) {
      return block.raw;
    }
    switch (block.kind) {
      case ContentBlockKind.HEADING:
        return `${'#'.repeat(Math.max(1, Math.min(6, block.level)))} ` +
          `${TriliumCodec.plainInline(block.segments)}`;
      case ContentBlockKind.CODE:
        return `\`\`\`${block.language}\n${block.codeLines.join('\n')}\n\`\`\``;
      case ContentBlockKind.PARAGRAPH:
        return TriliumCodec.plainInline(block.segments);
      default:
        return block.raw.length > 0 ? block.raw : block.text;
    }
  }

  private static plainInline(segments: InlineSegment[]): string {
    let text: string = '';
    for (let i = 0; i < segments.length; i++) {
      text += segments[i].text;
    }
    return text;
  }

  private static escapeHtml(value: string): string {
    return value.replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }
}
