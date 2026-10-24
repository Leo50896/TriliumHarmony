import { LengthMetrics } from '@kit.ArkUI';
import { InlineSegment } from '../utils/HtmlContentParser';

/**
 * Renders inline HTML as a single native Text flow.
 *
 * ContainerSpan is used for inline code. It has no padding attribute, so the
 * horizontal padding is emulated with transparent NBSP spans inside the
 * container: the container background covers the NBSP + code + NBSP run.
 *
 * Span only exposes onClick/onHover (not onTouch), so link press feedback is
 * driven by onClick/onHover and kept for a short moment after the tap.
 */
@Component
export struct InlineTextView {
  @Prop segments: InlineSegment[] = [];
  @Prop fontSize: number = 17;
  @Prop lineHeight: number = 28;
  @Prop color: ResourceColor = $r('app.color.text_primary');
  @Prop weight: FontWeight = FontWeight.Normal;
  @Prop italic: boolean = false;
  onLink: (href: string) => void = () => {};
  onTap: () => void = () => {};

  @State private pressedKey: string = '';
  @StorageLink('TEXT_SELECTION_DISMISS') @Watch('dismissSelection') private dismissTick: number = 0;
  private textController: TextController = new TextController();

  private dismissSelection(): void {
    try {
      this.textController.closeSelectionMenu();
      this.textController.setTextSelection(0, 0);
    } catch (error) {
      // The Text may not be mounted yet.
    }
  }

  private keyFor(segment: InlineSegment, index: number): string {
    return `${index}-${segment.text}-${segment.bold ? 1 : 0}${segment.italic ? 1 : 0}` +
      `${segment.code ? 1 : 0}-${segment.href}-${segment.color}-${segment.backgroundColor}`;
  }

  private pressLink(segment: InlineSegment, index: number): void {
    this.pressedKey = this.keyFor(segment, index);
    this.onLink(segment.href);
    setTimeout(() => {
      if (this.pressedKey === this.keyFor(segment, index)) {
        this.pressedKey = '';
      }
    }, 180);
  }

  private hoverLink(segment: InlineSegment, index: number, hover: boolean): void {
    if (hover) {
      this.pressedKey = this.keyFor(segment, index);
    } else if (this.pressedKey === this.keyFor(segment, index)) {
      this.pressedKey = '';
    }
  }

  private isPressed(segment: InlineSegment, index: number): boolean {
    return this.pressedKey === this.keyFor(segment, index);
  }

  @Builder
  private InlineSegmentView(segment: InlineSegment, index: number) {
    if (segment.code) {
      ContainerSpan() {
        Span('\u00A0')
          .fontSize(this.fontSize * 0.8)
          .fontColor(Color.Transparent)
        Span(segment.text)
          .fontFamily('monospace')
          .fontSize(this.fontSize * 0.8)
          .fontColor(segment.color.length > 0 ? segment.color : this.color)
        Span('\u00A0')
          .fontSize(this.fontSize * 0.8)
          .fontColor(Color.Transparent)
      }
      .textBackgroundStyle({
        color: segment.backgroundColor.length > 0 ? segment.backgroundColor : $r('app.color.inline_code_bg'),
        radius: 5
      })
    } else if (segment.href.length > 0) {
      Span(segment.text)
        .fontSize(segment.href.startsWith('#fn') ? this.fontSize * 0.68 : this.fontSize)
        .baselineOffset(LengthMetrics.vp(segment.href.startsWith('#fn') ? 4 : 0))
        .fontColor(this.isPressed(segment, index) ? $r('app.color.inline_link_pressed') :
          (segment.color.length > 0 ? segment.color : $r('app.color.inline_link')))
        .fontWeight(segment.bold ? 600 : FontWeight.Medium)
        .fontStyle(segment.italic ? FontStyle.Italic : FontStyle.Normal)
        .decoration({
          type: TextDecorationType.Underline,
          color: segment.color.length > 0 ? segment.color : $r('app.color.inline_link')
        })
        .textBackgroundStyle({
          color: this.isPressed(segment, index) ? $r('app.color.bg_selected_soft') :
            (segment.backgroundColor.length > 0 ? segment.backgroundColor : Color.Transparent),
          radius: this.isPressed(segment, index) || segment.backgroundColor.length > 0 ? 4 : 0
        })
        .onHover((isHover: boolean) => {
          this.hoverLink(segment, index, isHover);
        })
        .onClick(() => {
          this.pressLink(segment, index);
        })
      if (segment.href.startsWith('http://') || segment.href.startsWith('https://')) {
        Span('↗')
          .fontSize(this.fontSize * 0.62)
          .fontColor(segment.color.length > 0 ? segment.color : $r('app.color.inline_link'))
      }
    } else {
      Span(segment.text)
        .fontColor(segment.color.length > 0 ? segment.color : this.color)
        .fontWeight(segment.bold ? 600 : this.weight)
        .fontStyle(segment.italic || this.italic ? FontStyle.Italic : FontStyle.Normal)
        .textBackgroundStyle({
          color: segment.backgroundColor.length > 0 ? segment.backgroundColor : Color.Transparent,
          radius: segment.backgroundColor.length > 0 ? 3 : 0
        })
    }
  }

  build() {
    Text('', { controller: this.textController }) {
      ForEach(this.segments, (segment: InlineSegment, index: number) => {
        this.InlineSegmentView(segment, index)
      }, (segment: InlineSegment, index: number) => this.keyFor(segment, index))
    }
    .fontSize(this.fontSize)
    .lineHeight(this.lineHeight)
    .fontColor(this.color)
    .fontWeight(this.weight)
    .fontStyle(this.italic ? FontStyle.Italic : FontStyle.Normal)
    .width('100%')
    .textAlign(TextAlign.Start)
    .copyOption(CopyOptions.LocalDevice)
    .onClick(() => {
      const tick: number = AppStorage.get<number>('TEXT_SELECTION_DISMISS') ?? 0;
      AppStorage.setOrCreate('TEXT_SELECTION_DISMISS', tick + 1);
      if (this.pressedKey.length === 0) {
        this.onTap();
      }
    })
    .gesture(TapGesture({ count: 1 }).onAction(() => {
      if (this.pressedKey.length === 0) {
        this.onTap();
      }
    }))
  }
}
