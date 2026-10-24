import { InlineSegment } from '../utils/HtmlContentParser';

/**
 * Single-block inline editor for the block-based reading mode.
 *
 * The RichEditor holds only one paragraph/heading. Its spans are loaded from the
 * block's InlineSegment[] and converted back on blur, preserving bold, italic,
 * inline code and existing link hrefs.
 */
@Component
export struct BlockRichEditor {
  @Prop segments: InlineSegment[] = [];
  @Prop fontSize: number = 17;
  @Prop lineHeight: number = 28;
  @Prop heading: boolean = false;
  @Prop @Watch('onCommitTick') commitTick: number = 0;
  onCommit: (segments: InlineSegment[], text: string, headingLevel?: number) => void = () => {};
  onEditorFocus: () => void = () => {};

  private controller: RichEditorController = new RichEditorController();
  private loaded: boolean = false;
  private originalText: string = '';
  @State private boldActive: boolean = false;
  @State private italicActive: boolean = false;
  @State private strikeActive: boolean = false;
  @State private h1Active: boolean = false;
  @State private h2Active: boolean = false;
  private collapsedStyleUpdate: boolean = false;
  private lastStyleOffset: number = -1;
  private boldOverride: boolean | null = null;
  private italicOverride: boolean | null = null;

  aboutToAppear(): void {
    this.originalText = this.textOf(this.segments);
    let allBold: boolean = this.segments.length > 0;
    let allItalic: boolean = this.segments.length > 0;
    for (let i = 0; i < this.segments.length; i++) {
      allBold = allBold && this.segments[i].bold;
      allItalic = allItalic && this.segments[i].italic;
    }
    this.boldActive = allBold;
    this.italicActive = allItalic;
    this.h1Active = this.heading && this.fontSize >= 26;
    this.h2Active = this.heading && this.fontSize >= 22 && this.fontSize < 26;
  }

  private onCommitTick(): void {
    if (this.loaded) {
      this.commit();
    }
  }

  private textOf(segments: InlineSegment[]): string {
    let text: string = '';
    for (let i = 0; i < segments.length; i++) {
      text += segments[i].text;
    }
    return text;
  }

  private textSpansOf(spans: Array<RichEditorTextSpanResult | RichEditorImageSpanResult>):
    RichEditorTextSpanResult[] {
    const result: RichEditorTextSpanResult[] = [];
    for (let i = 0; i < spans.length; i++) {
      const span = spans[i] as RichEditorTextSpanResult;
      if (span.textStyle !== undefined) {
        result.push(span);
      }
    }
    return result;
  }

  private refreshToolbarState(): void {
    if (!this.loaded || this.collapsedStyleUpdate) {
      return;
    }
    try {
      const selection = this.controller.getSelection();
      const start: number = selection.selection[0];
      const end: number = selection.selection[1];
      // Keep the last toolbar action stable for a collapsed caret. Refreshing
      // from spans here would immediately undo the button state because some
      // RichEditor builds only expose updated span styles after a text change.
      if (start === end) {
        return;
      }
      let spans = this.textSpansOf(selection.spans);
      let bold: boolean = spans.length > 0;
      let italic: boolean = spans.length > 0;
      let strike: boolean = false;
      let maxFont: number = 0;
      for (let i = 0; i < spans.length; i++) {
        const style = spans[i].textStyle;
        bold = bold && this.isBold(style);
        italic = italic && style.fontStyle === FontStyle.Italic;
        strike = strike || this.isStrike(style);
        const fontSize = style.fontSize;
        if (typeof fontSize === 'number') {
          maxFont = Math.max(maxFont, fontSize);
        }
      }
      if (start === end && spans.length === 0) {
        const typing = this.controller.getTypingStyle();
        bold = this.isBoldWeight(typing.fontWeight);
        italic = typing.fontStyle === FontStyle.Italic;
        if (typing.decoration !== undefined) {
          strike = typing.decoration.type === TextDecorationType.LineThrough;
        }
        if (typeof typing.fontSize === 'number') {
          maxFont = typing.fontSize;
        }
      }
      this.boldActive = bold;
      this.italicActive = italic;
      this.strikeActive = strike;
      this.h1Active = maxFont >= 26;
      this.h2Active = maxFont >= 22 && maxFont < 26;
    } catch (error) {
      // The controller may be detached while the block is unmounting.
    }
  }

  private isStrike(style: RichEditorTextStyleResult): boolean {
    const decoration = style.decoration;
    return decoration !== undefined && decoration.type === TextDecorationType.LineThrough;
  }

  private documentLength(): number {
    let length: number = 0;
    const spans = this.controller.getSpans();
    for (let i = 0; i < spans.length; i++) {
      const span = spans[i] as RichEditorTextSpanResult;
      if (span.value !== undefined) {
        length += span.value.length;
      }
    }
    return length;
  }

  private applyTextStyle(style: RichEditorTextStyle): void {
    try {
      const selection = this.controller.getSelection();
      const start: number = selection.selection[0];
      const end: number = selection.selection[1];
      if (start === end) {
        const rangeStart: number = 0;
        const rangeEnd: number = this.documentLength();
        if (rangeEnd > rangeStart) {
          this.collapsedStyleUpdate = true;
          this.lastStyleOffset = start;
          this.controller.updateSpanStyle({
            start: rangeStart,
            end: rangeEnd,
            textStyle: style
          });
          this.controller.setSelection(start, end);
          return;
        }
        const typing = this.controller.getTypingStyle();
        if (style.fontWeight !== undefined) {
          typing.fontWeight = style.fontWeight;
        }
        if (style.fontStyle !== undefined) {
          typing.fontStyle = style.fontStyle;
        }
        if (style.decoration !== undefined) {
          typing.decoration = style.decoration;
        }
        this.controller.setTypingStyle(typing);
      } else {
        this.controller.updateSpanStyle({
          start: start,
          end: end,
          textStyle: style
        });
        this.controller.setSelection(start, end);
      }
      this.refreshToolbarState();
    } catch (error) {
      // Ignore stale controller state.
    }
  }

  private selectionIsBold(): boolean {
    try {
      const selection = this.controller.getSelection();
      let spans = this.textSpansOf(selection.spans);
      if (selection.selection[0] === selection.selection[1]) {
        const allSpans = this.textSpansOf(this.controller.getSpans());
        for (let i = 0; i < allSpans.length; i++) {
          const range = allSpans[i].spanPosition.spanRange;
          if (selection.selection[0] >= range[0] && selection.selection[0] <= range[1]) {
            spans = [allSpans[i]];
            break;
          }
        }
      }
      for (let i = 0; i < spans.length; i++) {
        if (this.isBold(spans[i].textStyle)) {
          return true;
        }
      }
    } catch (error) {
      // Fall back to the toolbar state.
    }
    return this.boldActive;
  }

  private toggleBold(): void {
    // Read the actual span instead of trusting a cached button state. After a
    // saved bold paragraph the component can be reused with a stale active flag.
    const active: boolean = this.selectionIsBold();
    this.boldActive = !active;
    this.boldOverride = this.boldActive;
    this.applyTextStyle({ fontWeight: this.boldActive ? 700 : 400 });
  }

  private toggleItalic(): void {
    this.italicActive = !this.italicActive;
    this.italicOverride = this.italicActive;
    this.applyTextStyle({
      fontStyle: this.italicActive ? FontStyle.Italic : FontStyle.Normal
    });
  }

  private toggleStrike(): void {
    this.strikeActive = !this.strikeActive;
    this.applyTextStyle({
      decoration: {
        type: this.strikeActive ? TextDecorationType.LineThrough : TextDecorationType.None
      }
    });
  }

  private applyHeading(size: number, lineHeight: number): void {
    try {
      const selection = this.controller.getSelection();
      const rangeStart: number = 0;
      const rangeEnd: number = this.documentLength();
      if (rangeEnd <= rangeStart) {
        return;
      }
      this.controller.updateSpanStyle({
        start: rangeStart,
        end: rangeEnd,
        textStyle: {
          fontSize: size,
          lineHeight: lineHeight
        }
      });
      this.controller.setSelection(selection.selection[0], selection.selection[1]);
      this.h1Active = size >= 26;
      this.h2Active = size >= 22 && size < 26;
    } catch (error) {
      // Ignore stale ranges.
    }
  }

  @Builder
  private FormatToolbar() {
    Scroll() {
      Row({ space: 4 }) {
        Text('B')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.boldActive ? '#6cb6ff' : $r('app.color.text_secondary'))
          .width(38)
          .height(34)
          .textAlign(TextAlign.Center)
          .borderRadius(8)
          .backgroundColor(this.boldActive ? '#1f3b5c' : $r('app.color.bg_secondary'))
          .focusable(false)
          .onClick(() => {
            this.toggleBold();
          })
        Text('I')
          .fontSize(14)
          .fontStyle(FontStyle.Italic)
          .fontColor(this.italicActive ? '#6cb6ff' : $r('app.color.text_secondary'))
          .width(38)
          .height(34)
          .textAlign(TextAlign.Center)
          .borderRadius(8)
          .backgroundColor(this.italicActive ? '#1f3b5c' : $r('app.color.bg_secondary'))
          .focusable(false)
          .onClick(() => {
            this.toggleItalic();
          })
        Text('S')
          .fontSize(14)
          .decoration({ type: TextDecorationType.LineThrough })
          .fontColor(this.strikeActive ? '#6cb6ff' : $r('app.color.text_secondary'))
          .width(38)
          .height(34)
          .textAlign(TextAlign.Center)
          .borderRadius(8)
          .backgroundColor(this.strikeActive ? '#1f3b5c' : $r('app.color.bg_secondary'))
          .focusable(false)
          .onClick(() => {
            this.toggleStrike();
          })
        Text('H1')
          .fontSize(14)
          .fontColor(this.h1Active ? '#6cb6ff' : $r('app.color.text_secondary'))
          .width(38)
          .height(34)
          .textAlign(TextAlign.Center)
          .borderRadius(8)
          .backgroundColor(this.h1Active ? '#1f3b5c' : $r('app.color.bg_secondary'))
          .focusable(false)
          .onClick(() => {
            this.applyHeading(28, 38);
          })
        Text('H2')
          .fontSize(14)
          .fontColor(this.h2Active ? '#6cb6ff' : $r('app.color.text_secondary'))
          .width(38)
          .height(34)
          .textAlign(TextAlign.Center)
          .borderRadius(8)
          .backgroundColor(this.h2Active ? '#1f3b5c' : $r('app.color.bg_secondary'))
          .focusable(false)
          .onClick(() => {
            this.applyHeading(23, 32);
          })
      }
      .height(40)
      .padding({ left: 2, right: 2 })
      .focusable(false)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(40)
    .focusable(false)
  }

  private loadSpans(): void {
    if (this.loaded) {
      return;
    }
    this.loaded = true;
    try {
      this.controller.deleteSpans();
    } catch (error) {
      // The controller may not be attached yet.
    }
    for (let i = 0; i < this.segments.length; i++) {
      const segment: InlineSegment = this.segments[i];
      if (segment.text.length === 0) {
        continue;
      }
      this.controller.addTextSpan(segment.text, {
        style: this.styleFor(segment)
      });
    }
    setTimeout(() => {
      try {
        this.getUIContext().getFocusController().requestFocus('block-rich-editor');
        this.controller.setSelection(this.originalText.length, this.originalText.length);
      } catch (error) {
        // Focus is best-effort; the user can tap the editor again.
      }
      this.onEditorFocus();
    }, 120);
  }

  private styleFor(segment: InlineSegment): RichEditorTextStyle {
    const style: RichEditorTextStyle = {
      fontColor: segment.href.length > 0 ? '#4a90e2' : $r('app.color.text_primary'),
      fontSize: this.fontSize,
      fontWeight: segment.bold ? FontWeight.Bold :
        (this.heading ? FontWeight.Medium : FontWeight.Normal),
      fontStyle: segment.italic ? FontStyle.Italic : FontStyle.Normal
    };
    if (segment.code) {
      style.fontFamily = 'monospace';
      style.fontColor = '#d19a66';
    }
    if (segment.href.length > 0) {
      style.decoration = {
        type: TextDecorationType.Underline,
        color: '#4a90e2'
      };
    }
    return style;
  }

  private isBold(style: RichEditorTextStyleResult): boolean {
    return this.isBoldWeight(style.fontWeight);
  }

  private isBoldWeight(weight: number | FontWeight | string | undefined): boolean {
    if (typeof weight === 'number') {
      // RichEditorTextStyleResult normalizes FontWeight to numeric values:
      // 400 = normal, 500 = medium, 600 = semibold, 700 = bold.
      return weight >= 600;
    }
    if (typeof weight === 'string') {
      return weight === 'bold' || weight === '600' || weight === '700' || weight === '800';
    }
    return false;
  }

  private isCode(style: RichEditorTextStyleResult): boolean {
    const family = style.fontFamily;
    if (family === undefined) {
      return false;
    }
    return `${family}`.toLowerCase().indexOf('mono') >= 0;
  }

  private buildSegments(): InlineSegment[] {
    const spans = this.controller.getSpans();
    const segments: InlineSegment[] = [];
    for (let i = 0; i < spans.length; i++) {
      const span = spans[i] as RichEditorTextSpanResult;
      const value: string = span.value ?? '';
      if (value.length === 0) {
        continue;
      }
      const style: RichEditorTextStyleResult = span.textStyle;
      const bold: boolean = this.boldOverride !== null ? this.boldOverride : this.isBold(style);
      const italic: boolean = this.italicOverride !== null ? this.italicOverride :
        style.fontStyle === FontStyle.Italic;
      segments.push(new InlineSegment(value, bold, italic, this.isCode(style)));
    }
    return this.restoreLinks(segments);
  }

  /**
   * RichEditor has no href span style. Hrefs are restored from the original
   * segments: unchanged labels keep their link, even when the surrounding text
   * was edited. Editing a link label itself turns it into plain styled text.
   */
  private restoreLinks(segments: InlineSegment[]): InlineSegment[] {
    const newText: string = this.textOf(segments);
    const hrefs: string[] = new Array<string>(newText.length).fill('');
    let anyLink: boolean = false;
    let searchFrom: number = 0;
    for (let i = 0; i < this.segments.length; i++) {
      const original: InlineSegment = this.segments[i];
      if (original.href.length === 0 || original.text.length === 0) {
        continue;
      }
      let at: number = newText.indexOf(original.text, searchFrom);
      if (at < 0) {
        at = newText.indexOf(original.text);
      }
      if (at < 0) {
        continue;
      }
      for (let j = 0; j < original.text.length; j++) {
        hrefs[at + j] = original.href;
      }
      anyLink = true;
      searchFrom = at + original.text.length;
    }
    if (!anyLink) {
      return segments;
    }

    const result: InlineSegment[] = [];
    let offset: number = 0;
    for (let i = 0; i < segments.length; i++) {
      const segment: InlineSegment = segments[i];
      let groupStart: number = 0;
      let currentHref: string = offset < hrefs.length ? hrefs[offset] : '';
      for (let j = 1; j <= segment.text.length; j++) {
        const nextHref: string = offset + j < hrefs.length ? hrefs[offset + j] : '';
        if (j === segment.text.length || nextHref !== currentHref) {
          const part: string = segment.text.substring(groupStart, j);
          result.push(new InlineSegment(part, segment.bold, segment.italic, segment.code,
            currentHref));
          groupStart = j;
          currentHref = nextHref;
        }
      }
      offset += segment.text.length;
    }
    return result;
  }

  private commit(): void {
    const segments: InlineSegment[] = this.buildSegments();
    const headingLevel: number = this.h1Active ? 1 : (this.h2Active ? 2 : 0);
    this.onCommit(segments, this.textOf(segments), headingLevel);
  }

  build() {
    Column({ space: 4 }) {
      this.FormatToolbar()

      RichEditor({ controller: this.controller })
        .id('block-rich-editor')
        .width('100%')
        .constraintSize({
          minHeight: this.lineHeight + 10,
          maxHeight: 420
        })
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: $r('app.color.primary'), radius: 6 })
        .padding({ top: 4, bottom: 4, left: 2, right: 2 })
        .onReady(() => {
          this.loadSpans();
        })
        .onFocus(() => {
          this.onEditorFocus();
        })
        .onSelectionChange((range: RichEditorRange) => {
          if (range.start !== range.end || range.start !== this.lastStyleOffset) {
            this.collapsedStyleUpdate = false;
          }
          this.refreshToolbarState();
        })
        .onDidChange(() => {
          this.refreshToolbarState();
        })
        .onBlur(() => {
          this.commit();
        })
        .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean, currentRatio: number) => {
          if (this.loaded && !isVisible) {
            this.commit();
          }
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
