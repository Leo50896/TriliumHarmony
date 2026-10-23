import { pdfService, pdfViewManager, PdfView } from '@kit.PDFKit';
import deviceInfo from '@ohos.deviceInfo';

class PdfOutlineItem {
  title: string;
  pageIndex: number;
  level: number;

  constructor(title: string, pageIndex: number, level: number) {
    this.title = title;
    this.pageIndex = pageIndex;
    this.level = level;
  }
}

/**
 * Native PDF reader backed by the official PDF Kit.
 *
 * The PdfView component owns rendering and gestures. This wrapper owns loading,
 * outline extraction and the surrounding page background. It intentionally does
 * not render ArkUI overlays above PdfView: PdfView is a native surface and
 * overlays can tear during fast scrolling.
 */
@Component
export struct PdfViewer {
  @Prop sourcePath: string = '';
  @Prop sourceBuffer: ArrayBuffer | null = null;
  @Prop @Watch('onJumpPageChanged') jumpPage: number = -1;
  @Prop @Watch('onOutlineRequestChanged') outlineRequest: number = 0;
  onScrollChange: (offsetPixels: number) => void = () => {};
  onPageChanged: (pageIndex: number) => void = () => {};
  onOutlineReady: (titles: string[], pages: number[], count: number) => void = () => {};
  @StorageProp('colorMode') private colorMode: number = 0;

  @State private isLoading: boolean = true;
  @State private errorMessage: string = '';
  private pageCount: number = 0;
  private preloadTimer: number = -1;
  private controller: pdfViewManager.PdfController = new pdfViewManager.PdfController();

  private pdfSupported(): boolean {
    try {
      // PDF Kit is an HMS service. The OpenHarmony emulator exposes the
      // syscap but has no PDF service implementation.
      if (deviceInfo.productModel.toLowerCase().indexOf('emulator') >= 0) {
        return false;
      }
      return canIUse('SystemCapability.OfficeService.PDFService.Core');
    } catch (error) {
      return false;
    }
  }

  private isPdfBuffer(buffer: ArrayBuffer): boolean {
    if (buffer.byteLength < 5) {
      return false;
    }
    const bytes: Uint8Array = new Uint8Array(buffer, 0, 5);
    return String.fromCharCode(bytes[0], bytes[1], bytes[2], bytes[3]) === '%PDF';
  }

  aboutToAppear(): void {
    setTimeout(() => {
      this.configureNestedScroll();
      this.loadPdf();
    }, 0);
  }

  private configureNestedScroll(): void {
    try {
      this.controller.setNestedScroll({
        scrollUp: pdfViewManager.PdfNestedScrollMode.SELF_FIRST,
        scrollDown: pdfViewManager.PdfNestedScrollMode.SELF_FIRST,
        scrollLeft: pdfViewManager.PdfNestedScrollMode.SELF_FIRST,
        scrollRight: pdfViewManager.PdfNestedScrollMode.SELF_FIRST
      });
    } catch (error) {
      // Older PDF Kit builds may not expose nested scrolling.
    }
  }

  aboutToDisappear(): void {
    if (this.preloadTimer >= 0) {
      clearTimeout(this.preloadTimer);
      this.preloadTimer = -1;
    }
    try {
      this.controller.releaseDocument();
    } catch (error) {
      // No document was loaded, or the platform already released it.
    }
  }

  private async loadPdf(): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';
    if (!this.pdfSupported()) {
      this.errorMessage = deviceInfo.productModel.toLowerCase().indexOf('emulator') >= 0
        ? '模拟器不支持 PDF Kit，请使用真机预览'
        : '当前设备不支持 PDF 预览';
      this.isLoading = false;
      return;
    }
    try {
      if (this.sourceBuffer !== null && this.sourceBuffer !== undefined) {
        if (!this.isPdfBuffer(this.sourceBuffer)) {
          this.errorMessage = '文件不是有效 PDF';
          this.isLoading = false;
          return;
        }
        const result: pdfService.ParseResult =
          await this.controller.loadDocumentFromMemory(this.sourceBuffer, '', 0);
        if (result === pdfService.ParseResult.PARSE_ERROR_PASSWORD) {
          this.errorMessage = '该 PDF 已加密，暂不支持预览';
        } else if (result !== pdfService.ParseResult.PARSE_SUCCESS) {
          this.errorMessage = 'PDF 解析失败';
        } else {
          this.refreshPageState();
          this.registerScroll();
        }
      } else if (this.sourcePath.length > 0) {
        const result: pdfService.ParseResult =
          await this.controller.loadDocument(this.sourcePath, '', 0);
        if (result === pdfService.ParseResult.PARSE_ERROR_PASSWORD) {
          this.errorMessage = '该 PDF 已加密，暂不支持预览';
        } else if (result !== pdfService.ParseResult.PARSE_SUCCESS) {
          this.errorMessage = 'PDF 解析失败';
        } else {
          this.refreshPageState();
          this.registerScroll();
        }
      } else {
        this.errorMessage = 'PDF 文件为空';
      }
    } catch (error) {
      const message: string = error instanceof Error ? error.message : `${error}`;
      this.errorMessage = message.toLowerCase().indexOf('password') >= 0 ||
        message.toLowerCase().indexOf('encrypted') >= 0
        ? '该 PDF 已加密，暂不支持预览' : 'PDF 加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  private refreshPageState(): void {
    setTimeout(() => {
      try {
        this.pageCount = this.controller.getPageCount();
        this.controller.registerPageChangedListener((index: number) => {
          this.onPageChanged(index);
          this.schedulePreload();
        });
        // Restored documents may already be on a later page.
        this.onPageChanged(this.controller.getPageIndex());
        this.preloadFirstPages();
      } catch (error) {
        // The controller may still be preparing the first page.
      }
    }, 300);
  }

  private preloadFirstPages(): void {
    const count: number = this.pageCount > 0 ? Math.min(3, this.pageCount) : 3;
    this.preloadPage(0, count);
  }

  private schedulePreload(): void {
    if (this.preloadTimer >= 0) {
      clearTimeout(this.preloadTimer);
    }
    // Let the currently visible page finish presenting before warming others.
    this.preloadTimer = setTimeout(() => {
      this.preloadTimer = -1;
      this.preloadFirstPages();
    }, 120);
  }

  private preloadPage(pageIndex: number, endExclusive: number): void {
    if (pageIndex >= endExclusive) {
      return;
    }
    try {
      // Warm the HD cache for the cover and the next two pages. Keep the
      // calls sequential so the PDF render thread is not flooded.
      this.controller.getPagePixelMap(pageIndex, false).then(() => {
        this.preloadPage(pageIndex + 1, endExclusive);
      }).catch(() => {
        this.preloadPage(pageIndex + 1, endExclusive);
      });
    } catch (error) {
      this.preloadPage(pageIndex + 1, endExclusive);
    }
  }

  private registerScroll(): void {
    try {
      this.controller.registerScrollListener((param: pdfViewManager.ScrollParam) => {
        this.onScrollChange(param.offsetY * param.pdfHeight);
      });
    } catch (error) {
      // Scroll notifications are optional; the PDF still renders.
    }
  }

  private onJumpPageChanged(): void {
    if (this.jumpPage < 0) {
      return;
    }
    try {
      if (this.jumpPage === 0) {
        const index: number = this.controller.getPageIndex();
        // Return-to-cover is unreliable through goToPage(0) on this PDF Kit
        // build (it can clamp to page 10~15). Reopen at page 0 and then
        // re-assert the top position after the first page is laid out.
        if (index > 0) {
          this.reloadAtFirstPage();
          return;
        }
      }
      this.controller.goToPage(this.jumpPage);
    } catch (error) {
      // Ignore an invalid page index.
    }
  }

  private async reloadAtFirstPage(): Promise<void> {
    try {
      this.controller.releaseDocument();
      let result: pdfService.ParseResult;
      if (this.sourcePath.length > 0) {
        result = await this.controller.loadDocument(this.sourcePath, '', 0);
      } else if (this.sourceBuffer !== null && this.sourceBuffer !== undefined) {
        result = await this.controller.loadDocumentFromMemory(this.sourceBuffer, '', 0);
      } else {
        return;
      }
      if (result === pdfService.ParseResult.PARSE_SUCCESS) {
        this.onPageChanged(0);
        this.pageCount = this.controller.getPageCount();
        this.schedulePreload();
        setTimeout(() => {
          try {
            this.controller.goToPage(0);
            this.onPageChanged(0);
          } catch (error) {
            // Keep the freshly opened page 0.
          }
        }, 120);
      }
    } catch (error) {
      // If reload fails, leave the current page untouched.
    }
  }

  private onOutlineRequestChanged(): void {
    // Opening a second PdfDocument is relatively expensive. Do it only when
    // the user opens the table of contents, never during normal reading.
    this.loadOutline();
  }

  private loadOutline(): void {
    if (this.sourcePath.length === 0) {
      return;
    }
    let document: pdfService.PdfDocument | null = null;
    try {
      document = new pdfService.PdfDocument();
      const result: pdfService.ParseResult = document.loadDocument(this.sourcePath);
      if (result === pdfService.ParseResult.PARSE_SUCCESS) {
        this.pageCount = document.getPageCount();
        const items: PdfOutlineItem[] = [];
        this.collectOutline(document.getRootBookmarks(), 0, items, 300);
        const titles: string[] = [];
        const pages: number[] = [];
        for (let i: number = 0; i < items.length; i++) {
          titles.push(items[i].title);
          pages.push(items[i].pageIndex);
        }
        this.onOutlineReady(titles, pages, this.pageCount);
      }
    } catch (error) {
      // Outline extraction is best-effort; page list remains available.
    } finally {
      if (document !== null) {
        try {
          document.releaseDocument();
        } catch (error) {
          // Already released.
        }
      }
    }
  }

  private collectOutline(bookmarks: pdfService.Bookmark[], level: number,
    items: PdfOutlineItem[], limit: number): void {
    for (let i: number = 0; i < bookmarks.length && items.length < limit; i++) {
      const bookmark: pdfService.Bookmark = bookmarks[i];
      try {
        const info: pdfService.BookmarkInfo = bookmark.getBookmarkInfo();
        const dest: pdfService.DestInfo = bookmark.getDestInfo();
        items.push(new PdfOutlineItem(info.title, dest.pageIndex, level));
        if (bookmark.hasChild()) {
          this.collectOutline(bookmark.getChildren(), level + 1, items, limit);
        }
      } catch (error) {
        // Skip a malformed bookmark rather than failing the whole outline.
      }
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.pdfSupported()) {
        PdfView({
          controller: this.controller,
          pageLayout: pdfService.PageLayout.LAYOUT_SINGLE,
          isContinuous: true,
          showScroll: true,
          pageFit: pdfService.PageFit.FIT_WIDTH
        })
          .width('100%')
          .height('100%')
          .onAppear(() => {
            this.configureNestedScroll();
          })
      }

      if (this.isLoading) {
        LoadingProgress()
          .width(28)
          .height(28)
          .color($r('app.color.primary'))
      } else if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .padding(16)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }
}
