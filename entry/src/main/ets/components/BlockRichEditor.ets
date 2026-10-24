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
  onCommit: (segments: InlineSegment[], text: string) => void = () => {};
  onEditorFocus: () => void = () => {};

  private controller: RichEditorController = new RichEditorController();
  private loaded: boolean = false;
  private committed: boolean = false;
  private originalText: string = '';

  aboutToAppear(): void {
    this.originalText = this.textOf(this.segments);
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
      fontWeight: this.heading || segment.bold ? FontWeight.Medium : FontWeight.Normal,
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
    const weight = style.fontWeight;
    if (typeof weight === 'number') {
      return weight >= 4;
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
      segments.push(new InlineSegment(value, this.isBold(style), style.fontStyle === FontStyle.Italic,
        this.isCode(style)));
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
    if (this.committed) {
      return;
    }
    this.committed = true;
    const segments: InlineSegment[] = this.buildSegments();
    this.onCommit(segments, this.textOf(segments));
  }

  build() {
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
      .onBlur(() => {
        this.commit();
      })
      .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean, currentRatio: number) => {
        if (this.loaded && !isVisible) {
          this.commit();
        }
      })
  }
}
