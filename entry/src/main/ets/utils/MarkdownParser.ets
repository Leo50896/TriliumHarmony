/**
 * Small Markdown → HTML converter used for code notes with
 * `#displayMode=preview` (the same mode Trilium uses to show Markdown rendered).
 *
 * It intentionally covers the constructs used by Markdown notes: headings,
 * paragraphs, bold/italic, inline code, links, fenced code, lists, quotes and
 * horizontal rules. The resulting HTML is fed to HtmlContentParser so the
 * native block readers stay shared.
 */
export class MarkdownParser {
  static toHtml(markdown: string): string {
    const lines: string[] = markdown.replace(/\r\n/g, '\n').split('\n');
    const out: string[] = [];
    let paragraph: string[] = [];
    let inFence: boolean = false;
    let fenceLanguage: string = '';
    let fenceLines: string[] = [];
    let listType: string = '';
    let listItems: string[] = [];
    let inQuote: boolean = false;
    let quoteLines: string[] = [];

    const flushParagraph = (): void => {
      if (paragraph.length > 0) {
        out.push(`<p>${MarkdownParser.inline(paragraph.join(' '))}</p>`);
        paragraph = [];
      }
    };
    const flushList = (): void => {
      if (listItems.length > 0) {
        out.push(`<${listType}>${listItems.join('')}</${listType}>`);
        listItems = [];
        listType = '';
      }
    };
    const flushQuote = (): void => {
      if (quoteLines.length > 0) {
        out.push(`<blockquote><p>${MarkdownParser.inline(quoteLines.join(' '))}</p></blockquote>`);
        quoteLines = [];
        inQuote = false;
      }
    };

    for (let i = 0; i < lines.length; i++) {
      const raw: string = lines[i];
      const line: string = raw.trimEnd();

      if (inFence) {
        if (/^```/.test(line)) {
          out.push(`<pre><code class="language-${fenceLanguage}">` +
            `${MarkdownParser.escape(fenceLines.join('\n'))}</code></pre>`);
          inFence = false;
          fenceLines = [];
          fenceLanguage = '';
        } else {
          fenceLines.push(raw);
        }
        continue;
      }

      if (/^```/.test(line)) {
        flushParagraph();
        flushList();
        flushQuote();
        inFence = true;
        fenceLanguage = line.substring(3).trim();
        continue;
      }

      if (line.trim().length === 0) {
        flushParagraph();
        flushList();
        flushQuote();
        continue;
      }

      if (i + 1 < lines.length && line.indexOf('|') >= 0 &&
        MarkdownParser.isTableSeparator(lines[i + 1])) {
        flushParagraph();
        flushList();
        flushQuote();
        const headers: string[] = MarkdownParser.splitCells(line);
        const rows: string[][] = [];
        i++;
        while (i + 1 < lines.length && lines[i + 1].trim().length > 0 &&
          lines[i + 1].indexOf('|') >= 0) {
          i++;
          rows.push(MarkdownParser.splitCells(lines[i]));
        }
        const headerHtml: string = headers.map((cell: string): string =>
          `<th>${MarkdownParser.inline(cell)}</th>`).join('');
        let bodyHtml: string = '';
        for (let r = 0; r < rows.length; r++) {
          const cells: string[] = rows[r];
          bodyHtml += '<tr>' + cells.map((cell: string): string =>
            `<td>${MarkdownParser.inline(cell)}</td>`).join('') + '</tr>';
        }
        out.push(`<table><thead><tr>${headerHtml}</tr></thead>` +
          `<tbody>${bodyHtml}</tbody></table>`);
        continue;
      }

      const heading: RegExpMatchArray | null = line.match(/^(#{1,6})\s+(.*)$/);
      if (heading !== null) {
        flushParagraph();
        flushList();
        flushQuote();
        const level: number = heading[1].length;
        out.push(`<h${level}>${MarkdownParser.inline(heading[2])}</h${level}>`);
        continue;
      }

      if (/^\s*(---+|\*\*\*+|___+)\s*$/.test(line)) {
        flushParagraph();
        flushList();
        flushQuote();
        out.push('<hr>');
        continue;
      }

      const quote: RegExpMatchArray | null = line.match(/^>\s?(.*)$/);
      if (quote !== null) {
        flushParagraph();
        flushList();
        inQuote = true;
        quoteLines.push(quote[1]);
        continue;
      }

      const bullet: RegExpMatchArray | null = line.match(/^\s*[-*+]\s+(.*)$/);
      if (bullet !== null) {
        flushParagraph();
        flushQuote();
        if (listType !== 'ul') {
          flushList();
          listType = 'ul';
        }
        listItems.push(`<li>${MarkdownParser.inline(bullet[1])}</li>`);
        continue;
      }

      const ordered: RegExpMatchArray | null = line.match(/^\s*\d+\.\s+(.*)$/);
      if (ordered !== null) {
        flushParagraph();
        flushQuote();
        if (listType !== 'ol') {
          flushList();
          listType = 'ol';
        }
        listItems.push(`<li>${MarkdownParser.inline(ordered[1])}</li>`);
        continue;
      }

      flushList();
      flushQuote();
      paragraph.push(line.trim());
    }

    if (inFence) {
      out.push(`<pre><code class="language-${fenceLanguage}">` +
        `${MarkdownParser.escape(fenceLines.join('\n'))}</code></pre>`);
    }
    flushParagraph();
    flushList();
    flushQuote();
    return out.join('\n');
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

  private static isTableSeparator(line: string): boolean {
    if (line.indexOf('-') < 0 || line.indexOf('|') < 0) {
      return false;
    }
    const cells: string[] = MarkdownParser.splitCells(line);
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

  private static inline(text: string): string {
    let value: string = MarkdownParser.escape(text);
    value = value.replace(/`([^`]+)`/g, '<code>$1</code>');
    value = value.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
    value = value.replace(/__([^_]+)__/g, '<strong>$1</strong>');
    value = value.replace(/\*([^*]+)\*/g, '<em>$1</em>');
    value = value.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>');
    return value;
  }

  private static escape(text: string): string {
    return text.replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }
}
