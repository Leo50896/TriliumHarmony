import { pasteboard } from '@kit.BasicServicesKit';
import { CodeHighlighter, CodeLine, CodeToken, CodeTokenKind } from '../utils/CodeHighlighter';
import { AppIcon } from './AppIcon';
import { StateKeys } from '../constants/StateKeys';

/**
 * Fenced code block with a tiny tokenizer-based highlighter.
 * The header mirrors the design: file name on the left, language pill and a
 * copy affordance on the right.
 */
@Component
export struct CodeBlock {
  @Prop fileName: string = 'index.ets';
  @Prop language: string = 'ARKTS';
  @Prop showHeader: boolean = true;
  @Prop showLineNumbers: boolean = true;
  @Prop sourceLines: string[] = [];
  onEdit: () => void = () => {};
  @StorageLink(StateKeys.READER_FONT_SIZE) private readerFontSize: number = 16;
  @State private copied: boolean = false;
  @State private showLanguageMenu: boolean = false;
  @State private selectedLanguage: string = '';
  @State private selecting: boolean = false;
  @State private selStart: number = -1;
  @State private selEnd: number = -1;
  @StorageLink('TEXT_SELECTION_DISMISS') @Watch('dismissSelection') private dismissTick: number = 0;
  private textController: TextController = new TextController();

  private codeWidth(): number {
    let maxChars: number = 0;
    for (let i = 0; i < this.sourceLines.length; i++) {
      maxChars = Math.max(maxChars, this.sourceLines[i].length);
    }
    return Math.max(320, maxChars * this.scaledFont(12.5) * 0.62 + 34);
  }

  private selectLine(lineIndex: number): void {
    const lines: string[] = this.sourceLines;
    const line: string = lines[lineIndex] ?? '';
    const start: number = this.sourceLines.slice(0, lineIndex).join('\n').length +
      (lineIndex > 0 ? 1 : 0);
    this.selStart = start;
    this.selEnd = start + line.length;
    this.textController.closeSelectionMenu();
    this.textController.setTextSelection(this.selStart, this.selEnd);
  }

  private dismissSelection(): void {
    try {
      this.textController.closeSelectionMenu();
      this.textController.setTextSelection(0, 0);
      this.selStart = -1;
      this.selEnd = -1;
    } catch (error) {
      // Not mounted.
    }
  }
  private languageNames: string[] = [
    '自动检测', 'Plain text', 'C', 'C#', 'C++', 'CSS', 'Elixir', 'Go',
    'Groovy', 'Haskell', 'HTML', 'HTTP', 'Java', 'JavaScript', 'JSON',
    'Kotlin', 'Markdown', 'Perl', 'PHP', 'Python', 'Ruby', 'Shell (bash)',
    'SQL', 'SQLite (Trilium)', 'Swift', 'TypeScript', 'XML', 'YAML'
  ];
  @State private highlightVersion: number = 0;

  aboutToAppear(): void {
  }

  private highlightedLines(): CodeLine[] {
    const target: string = this.selectedLanguage.length > 0 ?
      this.selectedLanguage : this.detectLanguage();
    return CodeHighlighter.highlight(this.sourceLines, target);
  }

  private colorFor(kind: CodeTokenKind): Resource {
    switch (kind) {
      case CodeTokenKind.KEYWORD:
        return $r('app.color.syntax_keyword');
      case CodeTokenKind.DECORATOR:
        return $r('app.color.syntax_decorator');
      case CodeTokenKind.STRING:
        return $r('app.color.syntax_string');
      case CodeTokenKind.NUMBER:
        return $r('app.color.syntax_number');
      case CodeTokenKind.COMMENT:
        return $r('app.color.syntax_comment');
      case CodeTokenKind.FUNCTION:
        return $r('app.color.syntax_function');
      case CodeTokenKind.PUNCTUATION:
        return $r('app.color.syntax_punctuation');
      default:
        return $r('app.color.syntax_plain');
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1400 });
    } catch (error) {
      // Toast is non-critical; copy still succeeded or failed independently.
    }
  }

  private async copyCode(): Promise<void> {
    try {
      const data: pasteboard.PasteData = pasteboard.createData(
        pasteboard.MIMETYPE_TEXT_PLAIN,
        this.sourceLines.join('\n')
      );
      await pasteboard.getSystemPasteboard().setData(data);
      this.copied = true;
      this.showToast('代码已复制');
      setTimeout(() => {
        this.copied = false;
      }, 1400);
    } catch (error) {
      this.showToast('复制失败，请稍后重试');
    }
  }

  private detectLanguage(): string {
    const text: string = this.sourceLines.join('\n').trim();
    if (text.length === 0) {
      return 'PLAIN TEXT';
    }
    const lower: string = text.toLowerCase();
    if (lower.startsWith('<?php')) {
      return 'PHP';
    }
    if (lower.startsWith('<?xml')) {
      return 'XML';
    }
    if (lower.startsWith('<!doctype html') || /<html[\s>]/i.test(text)) {
      return 'HTML';
    }
    if (text.startsWith('{') || text.startsWith('[')) {
      try {
        JSON.parse(text);
        return 'JSON';
      } catch (error) {
        // Not valid JSON; continue with other detectors.
      }
    }
    if (/^#!.*\b(bash|sh|zsh)\b/m.test(text)) {
      return 'SHELL';
    }
    if (/^(select|insert\s+into|update|delete\s+from|create\s+(table|index)|alter\s+table)\b/im.test(text)) {
      return 'SQL';
    }
    if (/^```/m.test(text) || /^#{1,6}\s+\S/m.test(text)) {
      return 'MARKDOWN';
    }
    if (/^[A-Z]+\s+\/\S+\s+HTTP\/\d\.\d/m.test(text)) {
      return 'HTTP';
    }
    const yamlLines: string[] = text.split('\n');
    let yamlKeys: number = 0;
    for (let index: number = 0; index < yamlLines.length; index++) {
      if (/^\s*[\w.-]+\s*:\s*/.test(yamlLines[index])) {
        yamlKeys++;
      }
    }
    if (yamlKeys >= 2 || /^\s*-\s+\S/m.test(text)) {
      return 'YAML';
    }
    if (/\{[^}]*[a-z-]+\s*:\s*[^}]+;?\s*\}/i.test(text) &&
      !/function|=>|class\s+\w+/.test(text)) {
      return 'CSS';
    }
    if (/\bdefmodule\b|\|>/.test(text)) {
      return 'ELIXIR';
    }
    if (/\b(def|class)\s+\w+|puts\b|\bend\b/.test(text) && !/\bfunction\b/.test(text)) {
      return 'RUBY';
    }
    if (/#include\s*<(iostream|vector|string|memory)>|std::/.test(text)) {
      return 'C++';
    }
    if (/#include\s*<[a-z_]+\.h>|\bint\s+main\s*\(/.test(text)) {
      return 'C';
    }
    if (/\busing\s+System\s*;|\bnamespace\s+\w+|\bConsole\.WriteLine\b/.test(text)) {
      return 'C#';
    }
    if (/\bpackage\s+\w+;|\bpublic\s+(static\s+)?(void|class)\b|\bSystem\.out\./.test(text)) {
      return 'JAVA';
    }
    if (/\bfun\s+\w+|\bval\s+\w+|\bvar\s+\w+/.test(text) && !/\bfunction\b/.test(text)) {
      return 'KOTLIN';
    }
    if (/\bpackage\s+main\b|\bfunc\s+\w+\(|:=/.test(text)) {
      return 'GO';
    }
    if (/\bdef\s+\w+\(|\bimport\s+\w+$|\bprint\(/.test(text) && !/\bfunction\b/.test(text)) {
      return 'PYTHON';
    }
    if (/\binterface\s+\w+|\btype\s+\w+\s*=|\benum\s+\w+|\bimplements\s+\w+/.test(text)) {
      return 'TYPESCRIPT';
    }
    if (/\b(const|let|function)\s+\w+|\bconsole\.log\b|=>/.test(text)) {
      return 'JAVASCRIPT';
    }
    if (/\bmain\s*::\s*IO\b|^\w+\s*::\s*/m.test(text)) {
      return 'HASKELL';
    }
    if (/\buse\s+strict\b|\bmy\s+\$/.test(text)) {
      return 'PERL';
    }
    if (/\bdef\s+\w+\(|\bprintln\b/.test(text)) {
      return 'GROOVY';
    }
    if (/\bimport\s+Swift\b|\bfunc\s+\w+\(/.test(text)) {
      return 'SWIFT';
    }
    if (/\b(echo|cd|sudo|apt|docker|npm|git)\s+/.test(text)) {
      return 'SHELL';
    }
    return 'PLAIN TEXT';
  }

  private displayLanguage(): string {
    if (this.selectedLanguage.length > 0) {
      return this.selectedLanguage;
    }
    const value: string = this.language.trim().toLowerCase();
    if (value.length === 0 || value === 'code' || value === 'text' ||
      value.indexOf('trilium-auto') >= 0 || value === 'text/plain' ||
      value === 'plain text' || value.startsWith('text/x-')) {
      return '自动检测';
    }
    if (value === 'yml' || value.indexOf('yaml') >= 0) {
      return 'YAML';
    }
    if (value === 'js' || value === 'javascript') {
      return 'JAVASCRIPT';
    }
    if (value === 'ts' || value === 'typescript') {
      return 'TYPESCRIPT';
    }
    if (value === 'sh' || value === 'bash' || value === 'shell' || value === 'zsh') {
      return 'SHELL';
    }
    if (value === 'py' || value === 'python') {
      return 'PYTHON';
    }
    if (value === 'md' || value === 'markdown') {
      return 'MARKDOWN';
    }
    if (value === 'c#') {
      return 'C#';
    }
    if (value === 'c++') {
      return 'C++';
    }
    if (value === 'cs') {
      return 'C#';
    }
    if (value === 'cpp') {
      return 'C++';
    }
    if (value === 'kt') {
      return 'KOTLIN';
    }
    if (value === 'rb') {
      return 'RUBY';
    }
    if (value === 'rs') {
      return 'RUST';
    }
    if (value === 'sqlite' || value.indexOf('sqlite') >= 0) {
      return 'SQLITE (TRILIUM)';
    }
    if (value.startsWith('text/x-')) {
      return value.substring(7).toUpperCase();
    }
    return value.toUpperCase();
  }

  private scaledFont(base: number): number {
    return base * this.readerFontSize / 16;
  }

  @Builder
  private CodeText(token: CodeToken) {
    Text(token.text.replace(/ /g, '\u00A0'))
      .copyOption(CopyOptions.LocalDevice)
      .fontSize(this.scaledFont(12.5))
      .lineHeight(this.scaledFont(21))
      .fontColor(this.colorFor(token.kind))
      .fontFamily('monospace')
      .maxLines(1)
  }

  @Builder
  private LineNumber(lineNumber: number) {
    Text(`${lineNumber}`)
      .width(32)
      .height(this.scaledFont(21))
      .lineHeight(this.scaledFont(21))
      .fontSize(this.scaledFont(10))
      .fontColor($r('app.color.text_tertiary'))
      .fontFamily('monospace')
      .textAlign(TextAlign.End)
      .padding({ right: 8 })
      .opacity(0.45)
  }

  @Builder
  private LanguageMenu() {
    Scroll() {
      Column({ space: 2 }) {
        ForEach(this.languageNames, (name: string) => {
          Row() {
            if (name === (this.selectedLanguage.length > 0 ? this.selectedLanguage : '自动检测')) {
              AppIcon({
                icon: $r('app.media.ic_check'),
                iconSize: 12,
                tint: $r('app.color.primary')
              })
                .margin({ right: 6 })
            } else {
              Row().width(18)
            }
            Text(name)
              .fontSize(12)
              .fontColor(name === this.selectedLanguage || (name === '自动检测' &&
                this.selectedLanguage.length === 0) ? $r('app.color.primary') :
                $r('app.color.text_primary'))
          }
          .width('100%')
          .height(34)
          .padding({ left: 8, right: 10 })
          .borderRadius(7)
          .onClick(() => {
            this.highlightVersion++;
            this.selectedLanguage = name === '自动检测' ? '' : name;
            this.showLanguageMenu = false;
          })
        }, (name: string) => name)
      }
      .width('100%')
      .padding(6)
    }
    .width(184)
    .height(330)
    .scrollBar(BarState.Auto)
    .backgroundColor($r('app.color.bg_elevated'))
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.border') })
    .shadow({
      radius: 20,
      color: $r('app.color.shadow'),
      offsetX: 0,
      offsetY: 8
    })
  }

  build() {
    ForEach([this.highlightVersion], (renderEpoch: number) => {
      Column() {
        if (this.showHeader) {
        Row() {
        Blank()

        Row({ space: 10 }) {
          Text(this.selecting ? '完成' : '选择')
            .fontSize(10.5)
            .fontColor(this.selecting ? $r('app.color.primary') : $r('app.color.text_secondary'))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius(6)
            .backgroundColor($r('app.color.bg_surface_alt'))
            .onClick(() => {
              this.selecting = !this.selecting;
            })
          if (this.selecting) {
            Text('全选')
              .fontSize(10.5)
              .fontColor($r('app.color.text_secondary'))
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .borderRadius(6)
              .backgroundColor($r('app.color.bg_surface_alt'))
              .onClick(() => {
                this.selStart = 0;
                this.selEnd = this.sourceLines.join('\n').length;
                this.textController.setTextSelection(this.selStart, this.selEnd);
              })
          }
          Text(`${this.displayLanguage()} ▾`)
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_tertiary'))
            .letterSpacing(0.5)
            .padding({ left: 7, right: 7, top: 3, bottom: 3 })
            .borderRadius(5)
            .backgroundColor($r('app.color.bg_surface_alt'))
            .onClick(() => {
              this.showLanguageMenu = !this.showLanguageMenu;
            })
            .bindPopup(this.showLanguageMenu, {
              builder: this.LanguageMenu,
              placement: Placement.Bottom,
              popupColor: $r('app.color.bg_elevated'),
              onStateChange: (event: PopupStateChangeParam) => {
                if (!event.isVisible) {
                  this.showLanguageMenu = false;
                }
              }
            })
          Row({ space: 5 }) {
            AppIcon({
              icon: this.copied ? $r('app.media.ic_check') : $r('app.media.ic_copy'),
              iconSize: 14,
              tint: this.copied ? $r('app.color.success') : $r('app.color.text_secondary')
            })
            Text(this.copied ? '已复制' : '复制代码')
              .fontSize(10.5)
              .fontColor(this.copied ? $r('app.color.success') : $r('app.color.text_secondary'))
          }
          .height(28)
          .padding({ left: 8, right: 10 })
          .borderRadius(8)
          .backgroundColor($r('app.color.bg_surface_alt'))
          .onClick(() => {
            this.copyCode();
          })
        }
      }
      .width('100%')
      .height(42)
      .padding({ left: 14, right: 10 })
      .backgroundColor($r('app.color.code_header'))
      .border({ width: { bottom: 1 }, color: $r('app.color.code_border') })
        }

      if (!this.showHeader) {
        Row({ space: 8 }) {
          Blank()
          if (this.selecting) {
            Text('全选')
              .fontSize(10)
              .fontColor($r('app.color.text_secondary'))
              .padding({ left: 7, right: 7, top: 3, bottom: 3 })
              .borderRadius(6)
              .backgroundColor($r('app.color.bg_surface_alt'))
              .onClick(() => {
                this.selStart = 0;
                this.selEnd = this.sourceLines.join('\n').length;
                this.textController.setTextSelection(this.selStart, this.selEnd);
              })
          }
          Text(this.selecting ? '完成' : '选择')
            .fontSize(10)
            .fontColor(this.selecting ? $r('app.color.primary') : $r('app.color.text_secondary'))
            .padding({ left: 7, right: 7, top: 3, bottom: 3 })
            .borderRadius(6)
            .backgroundColor($r('app.color.bg_surface_alt'))
            .onClick(() => {
              this.selecting = !this.selecting;
            })
        }
        .width('100%')
        .height(28)
        .padding({ left: 10, right: 10 })
      }

      if (this.selecting) {
        Scroll() {
          Row() {
            Column() {
              ForEach(this.sourceLines, (line: string, lineIndex: number) => {
                Text(`${lineIndex + 1}`)
                  .width(38)
                  .textAlign(TextAlign.End)
                  .padding({ right: 7 })
                  .fontFamily('monospace')
                  .fontSize(this.scaledFont(12.5))
                  .lineHeight(this.scaledFont(21))
                  .fontColor($r('app.color.text_tertiary'))
                  .onClick(() => {
                    this.selectLine(lineIndex);
                  })
                  .gesture(TapGesture({ count: 2 }).onAction(() => {
                    this.selectLine(lineIndex);
                  }))
              }, (line: string, lineIndex: number) => `sel-line-${lineIndex}`)
            }
            .width(50)
            .padding({ top: 14, bottom: 14 })

            Scroll() {
              Text(this.sourceLines.join('\n'), { controller: this.textController })
                .width(this.codeWidth())
                .fontFamily('monospace')
                .fontSize(this.scaledFont(12.5))
                .lineHeight(this.scaledFont(21))
                .fontColor($r('app.color.text_primary'))
                .copyOption(CopyOptions.LocalDevice)
                .selection(this.selStart, this.selEnd)
                .padding({ left: 10, right: 14, top: 14, bottom: 14 })
            }
            .layoutWeight(1)
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }
        .height(360)
        .width('100%')
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Auto)
      } else {
      ForEach([this.highlightVersion], (highlightVersion: number) => {
        Row() {
          if (this.showLineNumbers) {
            Column() {
              ForEach(this.highlightedLines(), (line: CodeLine, lineIndex: number) => {
                this.LineNumber(lineIndex + 1)
              }, (line: CodeLine, lineIndex: number) => `num-${highlightVersion}-${lineIndex}`)
            }
            .width(40)
            .alignItems(HorizontalAlign.End)
            .padding({ top: 14, bottom: 14 })
          }

          Scroll() {
            Column() {
              ForEach(this.highlightedLines(), (line: CodeLine, lineIndex: number) => {
                Flex({ direction: FlexDirection.Row, wrap: FlexWrap.NoWrap, alignItems: ItemAlign.Start }) {
                  ForEach(line.tokens, (token: CodeToken, tokenIndex: number) => {
                    this.CodeText(token)
                  }, (token: CodeToken, tokenIndex: number) =>
                    `${highlightVersion}-${tokenIndex}-${token.kind}-${token.text}`)
                }
                .constraintSize({ minHeight: this.scaledFont(21) })
              }, (line: CodeLine, lineIndex: number) =>
                `line-${highlightVersion}-${lineIndex}`)
            }
            .alignItems(HorizontalAlign.Start)
            .constraintSize({ minWidth: '100%' })
            .padding({ right: 14, top: 14, bottom: 14 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.None)
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }, (highlightVersion: number) => `code-body-${highlightVersion}`)
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.code_bg'))
    .borderRadius(13)
    .border({ width: 1, color: $r('app.color.code_border') })
    .clip(true)
    }, (renderEpoch: number) => `code-block-${renderEpoch}`)
  }
}
