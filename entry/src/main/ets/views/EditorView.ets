import { common } from '@kit.AbilityKit';
import { AppIcon } from '../components/AppIcon';
import { CodeBlock } from '../components/CodeBlock';
import { FloatingToolbar } from '../components/FloatingToolbar';
import { InlineTextView } from '../components/InlineTextView';
import { LogoMark } from '../components/LogoMark';
import { SearchView } from '../components/SearchView';
import { TopNavigationBar } from '../components/TopNavigationBar';
import { TriliumImage } from '../components/TriliumImage';
import { window } from '@kit.ArkUI';
import { TriliumIncludeNote } from '../components/TriliumIncludeNote';
import { TriliumCollapsible } from '../components/TriliumCollapsible';
import { MermaidFlowchart } from '../components/MermaidFlowchart';
import { MermaidParser } from '../utils/MermaidParser';
import { MarkdownParser } from '../utils/MarkdownParser';
import { BOXICONS_ALL_MAP } from '../utils/BoxiconsMap';
import { TriliumTable } from '../components/TriliumTable';
import { NativeSheetView } from '../components/NativeSheetView';
import { PdfViewer } from '../components/PdfViewer';
import { TriliumCallout } from '../components/TriliumCallout';
import { AuthSession } from '../models/AuthModels';
import { CachedNote } from '../models/CacheModels';
import {
  ContentBlock,
  ContentBlockKind,
  FootnoteItem,
  HtmlContentParser,
  InlineSegment
} from '../utils/HtmlContentParser';
import { TriliumNote, EtapiAttributePayload } from '../models/TriliumModels';
import { StateKeys } from '../constants/StateKeys';
import { EtapiService } from '../services/EtapiService';
import { ExternalLinkLauncher } from '../services/ExternalLinkLauncher';
import { LocalNote, LocalStore } from '../services/LocalStore';
import { PdfDiskCache } from '../services/PdfDiskCache';
import { ReadingPositionStore } from '../services/ReadingPositionStore';
import { SessionStore } from '../services/SessionStore';
import { SyncService } from '../services/SyncService';
import { TriliumLinkRouter } from '../services/TriliumLinkRouter';
import { SheetParser } from '../utils/SheetParser';
import { AttributeVisuals } from '../utils/AttributeVisuals';

class AttributeRow {
  attributeId: string;
  type: string;
  name: string;
  value: string;
  owned: boolean;

  constructor(attributeId: string, type: string, name: string, value: string,
    owned: boolean = true) {
    this.attributeId = attributeId;
    this.type = type;
    this.name = name;
    this.value = value;
    this.owned = owned;
  }
}

class AttributeSchema {
  name: string;
  label: string;
  mode: string;
  options: string[];

  constructor(name: string, label: string, mode: string, options: string[]) {
    this.name = name;
    this.label = label;
    this.mode = mode;
    this.options = options;
  }
}

const ATTRIBUTE_SCHEMAS: AttributeSchema[] = [
  new AttributeSchema('iconClass', '图标', 'icon',
    ['bx bx-code', 'bx bx-code-alt', 'bx bx-note', 'bx bx-notepad', 'bx bx-book',
      'bx bx-book-open', 'bx bx-calendar', 'bx bx-check', 'bx bx-folder',
      'bx bx-grid-alt', 'bx bx-tag', 'bx bx-lock', 'bx bx-search', 'bx bx-cog',
      'bx bx-server', 'bx bx-sync', 'bx bx-palette', 'bx bx-user', 'bx bx-time']),
  new AttributeSchema('viewType', '视图类型', 'view', ['list', 'grid']),
  new AttributeSchema('color', '颜色', 'color', ['red', 'blue', 'green', 'yellow', 'purple', 'orange']),
  new AttributeSchema('status', '状态', 'status', ['active', 'done', 'archived', 'todo'])
];

class RichRun {
  text: string;
  bold: boolean;
  italic: boolean;
  fontSize: number;

  constructor(text: string, bold: boolean, italic: boolean, fontSize: number) {
    this.text = text;
    this.bold = bold;
    this.italic = italic;
    this.fontSize = fontSize;
  }
}

/**
 * Reader/editor surface for a real ETAPI note.
 *
 * Reading renders a small native block model parsed from Trilium's HTML.
 * "编辑" opens the lightweight RichEditor when the note only contains
 * paragraphs/headings and bold/italic runs; otherwise it falls back to the raw
 * HTML/source editor so tables, images and other complex content are never
 * destroyed by a lossy rich-text round-trip.
 */
@Component
export struct EditorView {
  @StorageLink('nav.selectedNoteId') @Watch('onNoteIdChanged') noteId: string = '';
  @StorageProp('auth.token') @Watch('onAuthChanged') private authToken: string = '';
  @StorageLink('nav.openGlobalSearch') @Watch('onOpenGlobalSearchChanged')
  private openSearchRequest: boolean = false;
  @StorageLink(StateKeys.EDITOR_CLOSE_SHEET) @Watch('onCloseSheetRequested')
  private closeSheetRequest: number = 0;
  onMenu: () => void = () => {};
  onMore: () => void = () => {};
  onDeleted: (parentNoteId: string) => void = () => {};
  onSessionExpired: () => void = () => {};
  onSwipeRight: () => void = () => {};
  private swipeStartX: number = 0;
  private swipeStartY: number = 0;
  private swipeTracking: boolean = false;

  @State private note: TriliumNote | null = null;
  @State private blocks: ContentBlock[] = [];
  @State private tags: string[] = [];
  @State private childNotes: TriliumNote[] = [];
  @State private childViewType: string = '';
  @State private noteColor: string = '';
  @State private isLoading: boolean = false;
  @State private errorMessage: string = '';
  @State @Watch('onSheetStateChanged') private showSearch: boolean = false;
  @State @Watch('onSheetStateChanged') private showAttributes: boolean = false;
  @State private attrRows: AttributeRow[] = [];
  @State private attrType: string = 'label';
  @State private attrName: string = '';
  @State private attrValue: string = '';
  @State private attrBusy: boolean = false;
  @State private attrMenuOpen: boolean = false;
  @State private attrInput: string = '';
  @State private attrPickerMode: string = '';
  @State private attrPickerName: string = '';
  @State private attrEditingId: string = '';
  @State private attrHexColor: string = '';
  @State private attrIconName: string = '';
  @State private iconWallOpen: boolean = false;
  @State private iconQuery: string = '';
  @State private pickerHue: number = 0;
  @State private pickerSaturation: number = 80;
  @StorageLink(StateKeys.READER_FONT_SIZE) private readerFontSize: number = 16;
  @State private pickerLightness: number = 50;
  private attrScroller: Scroller = new Scroller();
  private titleByNoteId: Map<string, string> = new Map();
  @State private isSpreadsheet: boolean = false;
  @State private markdownPreview: boolean = false;
  @State private spreadsheetContent: string = '';
  @State private pdfBuffer: ArrayBuffer | null = null;
  @State private pdfPath: string = '';
  @State private isPdf: boolean = false;
  @State @Watch('onSheetStateChanged') private pdfOutlineOpen: boolean = false;
  @State private pdfOutlineTitles: string[] = [];
  @State private pdfOutlinePages: number[] = [];
  @State private pdfPageCount: number = 0;
  @State private pdfJumpPage: number = -1;
  @State private pdfOutlineRequest: number = 0;
  @State private pdfScrollProgress: number = 0;
  @State private pdfHeaderHeight: number = 220;
  @State private pdfJumping: boolean = false;
  @State private pdfCurrentPage: number = 0;
  @State private pdfAtTop: boolean = false;
  @State private pdfViewerEpoch: number = 0;
  private pdfJumpTarget: number = -1;
  @State private sheetNames: string[] = [];
  @State private activeSheet: number = 0;
  @State private isOffline: boolean = false;
  @State private offlineLabel: string = '';
  @State private wordCount: number = 0;
  @State private modifiedLabel: string = '';
  @State private rawContent: string = '';
  @State @Watch('onEditingStateChanged') private isEditing: boolean = false;
  @State @Watch('onEditingStateChanged') private isRichEditing: boolean = false;
  @State private editTitle: string = '';
  @State private editContent: string = '';
  @State private isSaving: boolean = false;
  @State private toolbarY: number = 700;
  @State private editorViewportHeight: number = 0;
  @State private fullViewportHeight: number = 0;
  @State private keyboardInset: number = 0;
  @State private readingProgress: number = 0;
  @State private readingContentHeight: number = 0;
  @State private readingViewportHeight: number = 0;
  private lastReadingOffset: number = 0;

  private session: AuthSession | null = null;
  private loadSequence: number = 0;
  private loadedNoteId: string = '';
  private isRestoringScroll: boolean = false;
  private scroller: Scroller = new Scroller();
  private richController: RichEditorController = new RichEditorController();
  private richLoaded: boolean = false;

  private onEditingStateChanged(): void {
    AppStorage.setOrCreate(StateKeys.EDITOR_EDITING, this.isEditing || this.isRichEditing);
  }

  aboutToDisappear(): void {
    AppStorage.setOrCreate(StateKeys.EDITOR_EDITING, false);
  }

  aboutToAppear(): void {
    this.consumeSearchRequest();
    this.onSheetStateChanged();
    this.loadReferenceTitles();
    this.bindKeyboardHeight();
    if (this.noteId.length > 0) {
      this.loadNote();
    }
  }

  private bindKeyboardHeight(): void {
    const context: common.UIAbilityContext | null = this.hostContext();
    if (context === null) {
      return;
    }
    window.getLastWindow(context).then((mainWindow: window.Window) => {
      mainWindow.on('keyboardHeightChange', (height: number) => {
        this.keyboardInset = height > 0 ? px2vp(height) : 0;
        this.recomputeToolbarY();
      });
    }).catch(() => {
      // Keyboard tracking is best-effort; the resize fallback still applies.
    });
  }

  private recomputeToolbarY(): void {
    if (this.editorViewportHeight <= 0) {
      return;
    }
    const viewportY: number = this.editorViewportHeight - 66;
    if (this.fullViewportHeight <= 0 || this.keyboardInset <= 0) {
      this.toolbarY = viewportY;
      return;
    }
    this.toolbarY = this.fullViewportHeight - 44 - this.keyboardInset;
  }

  private onSheetStateChanged(): void {
    AppStorage.setOrCreate(StateKeys.EDITOR_SHEET_OPEN,
      this.showSearch || this.pdfOutlineOpen || this.showAttributes);
  }

  private onCloseSheetRequested(): void {
    this.showSearch = false;
    this.pdfOutlineOpen = false;
    this.showAttributes = false;
  }

  private onOpenGlobalSearchChanged(): void {
    this.consumeSearchRequest();
  }

  private consumeSearchRequest(): void {
    if (!this.openSearchRequest) {
      return;
    }
    this.openSearchRequest = false;
    this.showSearch = true;
  }

  private onNoteIdChanged(): void {
    this.persistScrollPosition();
    this.loadNote();
  }

  private onAuthChanged(): void {
    this.session = null;
    if (this.noteId.length > 0) {
      this.loadNote();
    }
  }

  private updateReadingProgress(offset: number): void {
    this.lastReadingOffset = offset;
    const scrollable: number = this.readingContentHeight - this.readingViewportHeight;
    if (scrollable <= 1) {
      this.readingProgress = 0;
      return;
    }
    this.readingProgress = Math.min(1, Math.max(0, offset / scrollable));
  }

  private persistScrollPosition(): void {
    if (this.loadedNoteId.length === 0 || this.isRestoringScroll) {
      return;
    }
    try {
      const offset: OffsetResult = this.scroller.currentOffset();
      ReadingPositionStore.save(this.loadedNoteId, offset.yOffset);
      this.updateReadingProgress(offset.yOffset);
    } catch (error) {
      // The Scroll component may not be attached yet.
    }
  }

  private restoreScrollPosition(noteId: string): void {
    const target: number = ReadingPositionStore.get(noteId);
    this.isRestoringScroll = true;
    setTimeout(() => {
      try {
        this.scroller.scrollTo({ xOffset: 0, yOffset: target });
      } catch (error) {
        // The new content may not be laid out yet.
      }
      setTimeout(() => {
        this.isRestoringScroll = false;
        this.updateReadingProgress(target);
      }, 120);
    }, 60);
  }

  private notify(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1600 });
    } catch (error) {
      // The UI remains usable when the toast service is unavailable.
    }
  }

  private async resolveSession(): Promise<AuthSession | null> {
    return SessionStore.currentSession();
  }

  private jumpToPdfPage(page: number): void {
    if (page === 0) {
      if (this.pdfAtTop && !this.pdfJumping) {
        return;
      }
      // Recreate the native PdfView at page 0. goToPage(0) can retain a
      // scroll offset and stop at page 10~15; a fresh view starts at the top.
      this.pdfJumpTarget = 0;
      this.pdfJumping = true;
      this.pdfScrollProgress = 0;
      this.pdfAtTop = false;
      this.pdfJumpPage = -1;
      this.pdfViewerEpoch++;
      setTimeout(() => {
        if (this.pdfJumping) {
          this.pdfJumping = false;
          this.pdfJumpTarget = -1;
          this.pdfCurrentPage = 0;
          this.pdfAtTop = true;
          this.pdfScrollProgress = 0;
        }
      }, 1500);
      return;
    }
    this.pdfJumpTarget = page;
    this.pdfJumping = true;
    this.pdfJumpPage = -1;
    setTimeout(() => {
      this.pdfJumpPage = page;
    }, 0);
    setTimeout(() => {
      if (this.pdfJumping) {
        this.pdfJumping = false;
        this.pdfJumpTarget = -1;
        this.pdfScrollProgress = 1;
      }
    }, 1200);
  }

  private onPdfPageChanged(pageIndex: number): void {
    this.pdfCurrentPage = pageIndex;
    this.pdfAtTop = pageIndex === 0;
    AppStorage.setOrCreate(StateKeys.PDF_CURRENT_PAGE, pageIndex);
    if (!this.pdfJumping) {
      return;
    }
    if (pageIndex === this.pdfJumpTarget) {
      this.pdfJumping = false;
      this.pdfJumpTarget = -1;
      this.pdfScrollProgress = pageIndex === 0 ? 0 : 1;
    }
  }

  private returnToNoteStart(): void {
    if (this.isPdf) {
      this.jumpToPdfPage(0);
      return;
    }
    try {
      this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
    } catch (error) {
      // The Scroll may not be mounted yet.
    }
  }

  private onPdfScroll(offsetPixels: number): void {
    if (this.pdfJumping) {
      return;
    }
    const distance: number = Math.max(offsetPixels, 0);
    this.pdfAtTop = distance < 2;
    this.pdfScrollProgress = Math.min(distance / Math.max(this.pdfHeaderHeight, 1), 1);
  }

  private isPdfNote(note: TriliumNote): boolean {
    const mime: string = note.mime !== undefined ? note.mime.toLowerCase() : '';
    const title: string = note.title !== undefined ? note.title.toLowerCase() : '';
    return note.type === 'pdf' || mime.indexOf('pdf') >= 0 || title.endsWith('.pdf');
  }

  private async loadNote(): Promise<void> {
    const sequence: number = ++this.loadSequence;
    console.info(`EDIT_LOAD_START target=${this.noteId} seq=${sequence}`);
    this.note = null;
    this.blocks = [];
    this.tags = [];
    this.childNotes = [];
    this.childViewType = '';
    this.noteColor = '';
    this.rawContent = '';
    this.loadedNoteId = '';
    this.isLoading = true;
    this.isEditing = false;
    this.isRichEditing = false;
    this.richLoaded = false;
    this.richController = new RichEditorController();
    try {
      this.richController.deleteSpans();
    } catch (error) {
      // RichEditor is not attached yet.
    }
    this.isSaving = false;
    this.errorMessage = '';
    this.isOffline = false;
    this.offlineLabel = '';
    this.isRestoringScroll = true;
    this.readingProgress = 0;
    this.lastReadingOffset = 0;
    this.readingContentHeight = 0;

    if (this.noteId.length === 0) {
      this.note = null;
      this.blocks = [];
      this.tags = [];
      this.childNotes = [];
      this.childViewType = '';
      this.noteColor = '';
      this.wordCount = 0;
      this.modifiedLabel = '';
      this.rawContent = '';
      this.isLoading = false;
      this.loadedNoteId = '';
      this.isSpreadsheet = false;
      this.spreadsheetContent = '';
      this.pdfBuffer = null;
      this.pdfPath = '';
      this.isPdf = false;
      this.pdfOutlineTitles = [];      this.pdfOutlinePages = [];
      this.pdfPageCount = 0;
      this.pdfJumpPage = -1;
      this.pdfScrollProgress = 0;
      this.pdfHeaderHeight = 220;
      this.pdfJumping = false;
      this.pdfJumpTarget = -1;
      this.pdfCurrentPage = 0;
      this.pdfAtTop = false;
      AppStorage.setOrCreate(StateKeys.PDF_CURRENT_PAGE, 0);
      this.sheetNames = [];
      this.activeSheet = 0;
      this.scrollToTop();
      this.isRestoringScroll = false;
      return;
    }

    this.isLoading = true;
    try {
      const local: LocalNote | null = await this.loadLocalNote();
      if (sequence !== this.loadSequence) {
        return;
      }
      if (local !== null && local.contentCached) {
        console.info(`EDIT_LOAD_LOCAL target=${this.noteId} id=${local.note.noteId} ` +
          `title=${local.note.title} len=${local.content.length}`);
        this.applyNote(local.note, local.content);
        this.isOffline = false;
        this.offlineLabel = '';
        this.loadedNoteId = local.note.noteId;
        this.isLoading = false;
        this.restoreScrollPosition(local.note.noteId);
        return;
      }

      if (this.session === null) {
        this.session = await this.resolveSession();
      }
      if (this.session === null) {
        throw new Error('AUTH_401');
      }

      const note: TriliumNote = await EtapiService.getNote(this.session, this.noteId);
      console.log('SHEET_PDF_META ' + JSON.stringify(note));
      let content: string = '';
      this.pdfBuffer = null;
      this.pdfPath = '';
      const isPdf: boolean = this.isPdfNote(note);
      this.isPdf = isPdf;
      if (isPdf && !note.isProtected) {
        const hostContext: common.Context | undefined = this.getUIContext().getHostContext();
        let cachedPath: string = '';
        if (hostContext !== undefined) {
          cachedPath = PdfDiskCache.find(hostContext as common.UIAbilityContext, note.noteId);
        }
        if (cachedPath.length > 0) {
          this.pdfPath = cachedPath;
        } else {
          const buffer: ArrayBuffer =
            await EtapiService.getNoteBinaryContent(this.session, note.noteId);
          console.log('SHEET_PDF_BYTES ' + note.noteId + ' ' + buffer.byteLength);
          if (hostContext !== undefined) {
            const savedPath: string = await PdfDiskCache.write(
              hostContext as common.UIAbilityContext, note.noteId, buffer);
            if (savedPath.length > 0) {
              this.pdfPath = savedPath;
            } else {
              this.pdfBuffer = buffer;
            }
          } else {
            this.pdfBuffer = buffer;
          }
        }
      } else if (note.type !== 'image' && note.type !== 'file' && !note.isProtected) {
        content = await EtapiService.getNoteContent(this.session, note.noteId);
      }
      if (sequence !== this.loadSequence) {
        return;
      }

      this.applyNote(note, content);
      console.info(`EDIT_LOAD_APPLIED id=${note.noteId} title=${note.title} ` +
        `selected=${this.noteId}`);
      this.isOffline = false;
      this.offlineLabel = '';
      this.loadedNoteId = note.noteId;
      this.restoreScrollPosition(note.noteId);
      this.cacheNote(note, content);
    } catch (error) {
      if (sequence !== this.loadSequence) {
        return;
      }
      if (error instanceof Error && error.message === 'AUTH_401') {
        this.isRestoringScroll = false;
        this.errorMessage = '登录状态已失效';
        this.onSessionExpired();
      } else {
        const cached: CachedNote | null = await this.loadCachedNote();
        if (sequence !== this.loadSequence) {
          return;
        }
        if (cached !== null) {
          this.applyCachedNote(cached);
        } else {
          this.isRestoringScroll = false;
          this.errorMessage = '网络不可用，且没有本地缓存';
        }
      }
    } finally {
      if (sequence === this.loadSequence) {
        this.isLoading = false;
      }
    }
  }

  private async loadReferenceTitles(): Promise<void> {
    const context: common.UIAbilityContext | null = this.hostContext();
    if (context === null) {
      return;
    }
    try {
      const notes: TriliumNote[] = await LocalStore.all(context, SessionStore.accountKey());
      this.titleByNoteId.clear();
      for (let i = 0; i < notes.length; i++) {
        this.titleByNoteId.set(notes[i].noteId, notes[i].title);
      }
      this.applyReferenceTitles();
    } catch (error) {
      // Title cache is best-effort.
    }
  }

  private resolveSegments(segments: InlineSegment[]): void {
    for (let i = 0; i < segments.length; i++) {
      const segment: InlineSegment = segments[i];
      const id: string = TriliumLinkRouter.noteIdFromHref(segment.href);
      if (id.length > 0 && this.titleByNoteId.has(id)) {
        const title: string = this.titleByNoteId.get(id) ?? '';
        if (title.length > 0) {
          segment.text = title;
        }
      }
    }
  }

  private resolveBlockTitles(blocks: ContentBlock[]): void {
    for (let i = 0; i < blocks.length; i++) {
      const block: ContentBlock = blocks[i];
      this.resolveSegments(block.segments);
      for (let j = 0; j < block.listItems.length; j++) {
        this.resolveSegments(block.listItems[j]);
      }
      if (block.table !== null) {
        for (let r = 0; r < block.table.rows.length; r++) {
          const row = block.table.rows[r];
          for (let c = 0; c < row.cells.length; c++) {
            this.resolveSegments(row.cells[c].segments);
          }
        }
      }
      if (block.callout !== null) {
        this.resolveBlockTitles(block.callout.blocks);
      }
      if (block.collapsible !== null) {
        this.resolveBlockTitles(block.collapsible.blocks);
      }
      if (block.quoteBlocks.length > 0) {
        this.resolveBlockTitles(block.quoteBlocks);
      }
    }
  }

  private applyReferenceTitles(): void {
    if (this.blocks.length === 0) {
      return;
    }
    this.resolveBlockTitles(this.blocks);
    this.blocks = this.blocks.slice();
  }

  private applyNote(note: TriliumNote, content: string): void {
    this.loadReferenceTitles();
    this.markdownPreview = false;
    this.note = note;
    this.tags = note.visibleLabels();
    this.childViewType = this.attributeValue(note, 'viewType');
    this.noteColor = this.attributeValue(note, 'color');
    this.loadChildNotes();
    this.modifiedLabel = this.formatModified(note.dateModified);
    this.rawContent = content;
    this.editTitle = note.title;
    this.editContent = content;
    this.isSpreadsheet = note.type === 'spreadsheet';
    this.isPdf = this.isPdfNote(note);
    this.pdfOutlineTitles = [];
    this.pdfOutlinePages = [];
    this.pdfPageCount = 0;
    this.pdfJumpPage = -1;
    this.pdfScrollProgress = 0;
    this.pdfHeaderHeight = 220;
    this.pdfJumping = false;
    this.pdfJumpTarget = -1;
    this.pdfCurrentPage = 0;
    this.pdfAtTop = false;
    AppStorage.setOrCreate(StateKeys.PDF_CURRENT_PAGE, 0);
    this.spreadsheetContent = this.isSpreadsheet ? content : '';
    if (this.isSpreadsheet) {
      try {
        this.sheetNames = SheetParser.sheetNames(content);
      } catch (error) {
        this.sheetNames = [];
      }
      this.activeSheet = 0;
      this.blocks = [];
      this.wordCount = 0;
    } else {
      const displayMode: string = this.attributeValue(note, 'displayMode').toLowerCase();
      const language: string = this.attributeValue(note, 'language').toLowerCase();
      const markdownPreview: boolean = note.type === 'code' && displayMode === 'preview' &&
        (language.indexOf('markdown') >= 0 || /^(#{1,6}\s|```)/m.test(content));
      const html: string = markdownPreview ? MarkdownParser.toHtml(content) : content;
      this.markdownPreview = markdownPreview;
      this.blocks = HtmlContentParser.parse(html,
        markdownPreview ? 'text' : note.type, markdownPreview ? 'text/html' : note.mime);
      this.applyReferenceTitles();
      this.wordCount = HtmlContentParser.plainText(this.blocks).replace(/[\s☐☑]/g, '').length;
    }
    this.errorMessage = '';
  }

  private applyCachedNote(cached: CachedNote): void {
    const note: TriliumNote = cached.toTriliumNote();
    this.applyNote(note, cached.content);
    if (note.type === 'pdf') {
      const context: common.UIAbilityContext | null = this.hostContext();
      this.pdfBuffer = null;
      this.pdfPath = context !== null ? PdfDiskCache.find(context, note.noteId) : '';
    }
    this.isOffline = true;
    this.offlineLabel = this.formatCacheTime(cached.cachedAt);
    this.loadedNoteId = note.noteId;
    this.restoreScrollPosition(note.noteId);
    this.notify('网络不可用，已载入离线缓存');
  }

  private hostContext(): common.UIAbilityContext | null {
    const context: common.Context | undefined = this.getUIContext().getHostContext();
    return context === undefined ? null : context as common.UIAbilityContext;
  }

  private async loadLocalNote(): Promise<LocalNote | null> {
    const context: common.UIAbilityContext | null = this.hostContext();
    if (context === null || this.noteId.length === 0) {
      return null;
    }
    try {
      return await LocalStore.get(context, SessionStore.accountKey(), this.noteId);
    } catch (error) {
      return null;
    }
  }

  private cacheNote(note: TriliumNote, content: string): void {
    if (note.noteId !== this.noteId) {
      return;
    }
    const context: common.UIAbilityContext | null = this.hostContext();
    if (context === null || content.length === 0) {
      return;
    }
    if (note.type !== 'text' && note.type !== 'code' && note.type !== 'spreadsheet') {
      return;
    }
    LocalStore.put(context, SessionStore.accountKey(), note, content)
      .catch(() => {
        // Local DB is best-effort; never block reading on a write failure.
      });
  }

  private async loadCachedNote(): Promise<CachedNote | null> {
    const context: common.UIAbilityContext | null = this.hostContext();
    if (context === null) {
      return null;
    }
    try {
      const local: LocalNote | null = await LocalStore.get(
        context, SessionStore.accountKey(), this.noteId);
      if (local === null) {
        return null;
      }
      return new CachedNote(local.note.noteId, local.note.title, local.note.type,
        local.note.mime, local.note.dateModified, local.note.visibleLabels(),
        local.note.isProtected, local.content, Date.now());
    } catch (error) {
      return null;
    }
  }

  private formatCacheTime(value: number): string {
    const date: Date = new Date(value);
    const hours: string = date.getHours().toString().padStart(2, '0');
    const minutes: string = date.getMinutes().toString().padStart(2, '0');
    return `${hours}:${minutes}`;
  }

  private formatModified(value: string): string {
    if (value.length >= 16) {
      return `${value.substring(0, 10)} ${value.substring(11, 16)}`;
    }
    return value;
  }

  private scrollToTop(): void {
    this.isRestoringScroll = true;
    setTimeout(() => {
      try {
        this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
      } catch (error) {
        // The Scroll component may not be laid out yet.
      }
      setTimeout(() => {
        this.isRestoringScroll = false;
      }, 60);
    }, 0);
  }

  private openSearch(): void {
    this.pdfOutlineOpen = false;
    this.showSearch = true;
  }

  private selectSearchResult(noteId: string): void {
    if (noteId.length === 0) {
      return;
    }
    AppStorage.setOrCreate(StateKeys.SELECTED_NOTE_ID, noteId);
    AppStorage.setOrCreate(StateKeys.SELECTED_NOTE_TITLE, '');
    this.showSearch = false;
  }

  private formatWordCount(value: number): string {
    const thousands: number = Math.floor(value / 1000);
    const remainder: number = value % 1000;
    if (thousands > 0) {
      return `${thousands},${remainder.toString().padStart(3, '0')}`;
    }
    return value.toString();
  }

  private typeLabel(): string {
    if (this.note === null) {
      return '';
    }
    if (this.note.type === 'text') {
      return '文本';
    }
    if (this.note.type === 'code') {
      return '代码';
    }
    if (this.note.type === 'book') {
      return '目录';
    }
    if (this.note.type === 'spreadsheet') {
      return '电子表格';
    }
    if (this.note.type === 'image') {
      return '图片';
    }
    if (this.note.type === 'file') {
      return '文件';
    }
    return this.note.type;
  }

  private isEditable(): boolean {
    return this.note !== null && !this.isOffline && this.note.type !== 'image' &&
      this.note.type !== 'file' && this.note.type !== 'spreadsheet' &&
      !this.note.isProtected;
  }

  private breadcrumbCrumbs(): string[] {
    return this.note === null ? ['Trilium'] : ['笔记'];
  }

  private breadcrumbActive(): string {
    return this.note === null ? '选择笔记' : this.note.title;
  }

  private beginEdit(): void {
    if (this.note === null || !this.editingTargetValid()) {
      return;
    }
    if (this.isOffline) {
      this.notify('离线缓存为只读，联网后可编辑');
      return;
    }
    this.editTitle = this.note.title;
    this.editContent = this.rawContent;
    if (this.isSimpleContent()) {
      this.isEditing = false;
      this.isRichEditing = true;
      this.richLoaded = false;
      this.notify('轻编辑：支持加粗、斜体、标题；复杂内容请切源码');
    } else {
      this.isEditing = true;
      this.isRichEditing = false;
      this.notify('复杂内容已回退到源码编辑');
    }
  }

  private isSimpleContent(): boolean {
    if (this.note === null || this.note.type !== 'text') {
      return false;
    }
    for (let blockIndex: number = 0; blockIndex < this.blocks.length; blockIndex++) {
      const block: ContentBlock = this.blocks[blockIndex];
      if (block.kind !== ContentBlockKind.PARAGRAPH &&
        block.kind !== ContentBlockKind.HEADING &&
        block.kind !== ContentBlockKind.LIST) {
        return false;
      }
      if (block.kind === ContentBlockKind.LIST) {
        continue;
      }
    }
    return true;
  }

  private cancelEdit(): void {
    if (this.note !== null) {
      this.editTitle = this.note.title;
      this.editContent = this.rawContent;
    }
    this.isEditing = false;
    this.isRichEditing = false;
    this.richLoaded = false;
  }

  private handleFloatingAction(action: string): void {
    if (!this.isEditing && !this.isRichEditing) {
      this.toggleEdit();
      this.notify('已进入编辑模式，可继续选择工具');
      return;
    }
    if (this.isRichEditing) {
      if (action === 'bold' || action === 'italic' || action === 'h1' || action === 'h2') {
        this.applyRichStyle(action);
      } else if (action === 'bullet') {
        this.insertRichText('• ');
      } else if (action === 'ordered') {
        this.insertRichText('1. ');
      } else if (action === 'checklist') {
        this.insertRichText('☐ ');
      } else if (action === 'quote') {
        this.insertRichText('> ');
      } else if (action === 'code') {
        this.insertRichText('\n```\n\n```\n');
      } else {
        this.notify('该工具需要源码模式');
      }
      return;
    }
    const sourceMode: boolean = this.note !== null && this.note.type === 'code';
    switch (action) {
      case 'bold':
        this.editContent += sourceMode ? '****' : '<strong></strong>';
        break;
      case 'italic':
        this.editContent += sourceMode ? '**' : '<em></em>';
        break;
      case 'h1':
        this.editContent += sourceMode ? '\n# ' : '\n<h1></h1>';
        break;
      case 'h2':
        this.editContent += sourceMode ? '\n## ' : '\n<h2></h2>';
        break;
      case 'paragraph':
        this.editContent += sourceMode ? '\n\n' : '\n<p></p>';
        break;
      case 'bullet':
        this.editContent += sourceMode ? '\n- ' : '\n<ul><li></li></ul>';
        break;
      case 'ordered':
        this.editContent += sourceMode ? '\n1. ' : '\n<ol><li></li></ol>';
        break;
      case 'checklist':
        this.editContent += sourceMode ? '\n- [ ] ' : '\n<ul><li>☐ </li></ul>';
        break;
      case 'code':
        this.editContent += sourceMode ? '\n' : '\n<pre><code></code></pre>';
        break;
      case 'quote':
        this.editContent += sourceMode ? '\n> ' : '\n<blockquote></blockquote>';
        break;
      case 'callout':
        this.editContent += sourceMode ? '\n> [!NOTE]\n> ' :
          '\n<aside class="admonition note"><p></p></aside>';
        break;
      case 'table':
        this.editContent += sourceMode ? '\n| | |\n|---|---|\n| | |' :
          '\n<table><tr><td></td><td></td></tr></table>';
        break;
      case 'image':
        this.editContent += sourceMode ? '\n![alt](url)' : '\n<img src="" alt="">';
        break;
      case 'include':
        this.editContent += '\n<section class="include-note" data-note-id=""></section>';
        break;
      case 'math':
        this.editContent += sourceMode ? '\n$$\n\n$$' : '\n<math></math>';
        break;
      case 'indent':
        this.editContent += sourceMode ? '\n  ' : '\n<div style="margin-left:2em"></div>';
        break;
      case 'outdent':
        this.notify('请选中需要减少缩进的段落');
        break;
      default:
        this.notify('该工具已保留入口，可在源码中继续编辑');
        break;
    }
  }

  private editingTargetValid(): boolean {
    if (this.isLoading || this.note === null || this.note.noteId !== this.noteId) {
      this.notify('正在加载当前笔记，请稍候');
      return false;
    }
    return true;
  }

  private toggleEdit(): void {
    if (this.isEditing || this.isRichEditing) {
      this.cancelEdit();
      return;
    }
    if (!this.editingTargetValid()) {
      return;
    }
    this.beginEdit();
  }

  private enterSourceEdit(): void {
    if (!this.editingTargetValid()) {
      return;
    }
    this.isRichEditing = false;
    this.isEditing = true;
    this.editContent = this.rawContent;
    this.notify('已切换到源码编辑');
  }

  private enterRichEdit(): void {
    if (!this.editingTargetValid()) {
      return;
    }
    if (!this.isSimpleContent()) {
      this.notify('包含表格/图片/列表等内容，只能使用源码编辑');
      return;
    }
    this.isEditing = false;
    this.isRichEditing = true;
    this.richController = new RichEditorController();
    this.richLoaded = false;
    setTimeout(() => {
      this.loadRichContent();
    }, 0);
    this.notify('已切换到轻编辑');
  }

  private loadRichContent(): void {
    if (!this.isRichEditing || this.richLoaded) {
      return;
    }
    this.richLoaded = true;
    try {
      this.richController.deleteSpans();
      this.richController.setTypingStyle({
        fontColor: $r('app.color.text_primary'),
        fontSize: 17,
        fontWeight: 400,
        fontStyle: FontStyle.Normal
      });

      for (let blockIndex: number = 0; blockIndex < this.blocks.length; blockIndex++) {
        const block: ContentBlock = this.blocks[blockIndex];
        const heading: boolean = block.kind === ContentBlockKind.HEADING;
        const size: number = heading ? (block.level === 1 ? 27 : 23) : 17;
        if (block.kind === ContentBlockKind.LIST) {
          for (let itemIndex: number = 0; itemIndex < block.listItems.length; itemIndex++) {
            const item: InlineSegment[] = block.listItems[itemIndex];
            const level: number = itemIndex < block.listLevels.length ? block.listLevels[itemIndex] : 0;
            const marker: string = itemIndex < block.listMarkers.length ? block.listMarkers[itemIndex] : '•';
            const indent: string = '  '.repeat(Math.max(level, 0));
            this.richController.addTextSpan(`${indent}${marker} ${HtmlContentParser.segmentsText(item)}\n`, {
              style: {
                fontColor: $r('app.color.text_primary'),
                fontSize: 17,
                fontWeight: 400,
                fontStyle: FontStyle.Normal
              }
            });
          }
          continue;
        }
        for (let segmentIndex: number = 0; segmentIndex < block.segments.length; segmentIndex++) {
          const segment: InlineSegment = block.segments[segmentIndex];
          if (segment.text.length === 0) {
            continue;
          }
          this.richController.addTextSpan(segment.text, {
            style: {
              fontColor: $r('app.color.text_primary'),
              fontSize: size,
              fontWeight: heading || segment.bold ? 600 : 400,
              fontStyle: segment.italic ? FontStyle.Italic : FontStyle.Normal
            }
          });
        }
        if (blockIndex < this.blocks.length - 1) {
          this.richController.addTextSpan('\n', {
            style: {
              fontColor: $r('app.color.text_primary'),
              fontSize: size,
              fontWeight: 400,
              fontStyle: FontStyle.Normal
            }
          });
        }
      }
    } catch (error) {
      this.isRichEditing = false;
      this.isEditing = true;
      this.editContent = this.rawContent;
      this.notify('轻编辑器加载失败，已回退源码');
    }
  }

  private insertRichText(text: string): void {
    try {
      const selection: RichEditorSelection = this.richController.getSelection();
      const offset: number = selection.selection[0];
      this.richController.addTextSpan(text, {
        offset: offset,
        style: {
          fontColor: $r('app.color.text_primary'),
          fontSize: 17,
          fontWeight: 400,
          fontStyle: FontStyle.Normal
        }
      });
      this.richController.setSelection(offset + text.length, offset + text.length);
    } catch (error) {
      this.notify('当前光标位置不可插入');
    }
  }

  private applyRichStyle(kind: string): void {
    const selection: RichEditorSelection = this.richController.getSelection();
    const start: number = selection.selection[0];
    const end: number = selection.selection[1];
    if (start === end) {
      this.notify('请先选中文字，再应用格式');
      return;
    }
    const style: RichEditorTextStyle = {};
    if (kind === 'bold') {
      style.fontWeight = 600;
    } else if (kind === 'italic') {
      style.fontStyle = FontStyle.Italic;
    } else if (kind === 'h1') {
      style.fontSize = 27;
      style.fontWeight = 600;
    } else if (kind === 'h2') {
      style.fontSize = 23;
      style.fontWeight = 600;
    }
    this.richController.updateSpanStyle({
      start: start,
      end: end,
      textStyle: style
    });
  }

  private escapeHtml(value: string): string {
    return value
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  private serializeRichHtml(): string {
    const spans: Array<RichEditorImageSpanResult | RichEditorTextSpanResult> =
      this.richController.getSpans();
    const paragraphs: RichRun[][] = [];
    let current: RichRun[] = [];

    for (let index: number = 0; index < spans.length; index++) {
      const span: RichEditorTextSpanResult = spans[index] as RichEditorTextSpanResult;
      const value: string = span.value ?? '';
      if (value.length === 0) {
        continue;
      }
      const style: RichEditorTextStyleResult = span.textStyle;
      const bold: boolean = style.fontWeight !== undefined && style.fontWeight >= 4;
      const italic: boolean = style.fontStyle === FontStyle.Italic;
      const size: number = style.fontSize !== undefined ? style.fontSize : 17;
      const parts: string[] = value.split('\n');
      for (let partIndex: number = 0; partIndex < parts.length; partIndex++) {
        if (parts[partIndex].length > 0) {
          current.push(new RichRun(parts[partIndex], bold, italic, size));
        }
        if (partIndex < parts.length - 1) {
          paragraphs.push(current);
          current = [];
        }
      }
    }
    if (current.length > 0) {
      paragraphs.push(current);
    }

    let html: string = '';
    for (let pIndex: number = 0; pIndex < paragraphs.length; pIndex++) {
      const runs: RichRun[] = paragraphs[pIndex];
      let text: string = '';
      let maxSize: number = 0;
      for (let runIndex: number = 0; runIndex < runs.length; runIndex++) {
        text += runs[runIndex].text;
        maxSize = Math.max(maxSize, runs[runIndex].fontSize);
      }
      if (text.trim().length === 0) {
        continue;
      }
      const listMatch: RegExpMatchArray | null =
        text.match(/^(\s*)(•|\d+\.)\s+(.*)$/);
      if (listMatch !== null) {
        const level: number = Math.floor(listMatch[1].length / 2);
        const ordered: boolean = listMatch[2] !== '•';
        const listTag: string = ordered ? 'ol' : 'ul';
        html += `<${listTag}><li style="margin-left:${level * 24}px">` +
          `${this.escapeHtml(listMatch[3])}</li></${listTag}>`;
        continue;
      }
      const tag: string = maxSize >= 26 ? 'h1' : (maxSize >= 21 ? 'h2' : 'p');
      const headingTag: boolean = tag !== 'p';
      html += `<${tag}>`;
      for (let runIndex: number = 0; runIndex < runs.length; runIndex++) {
        const run: RichRun = runs[runIndex];
        let value: string = this.escapeHtml(run.text);
        if (run.italic) {
          value = `<em>${value}</em>`;
        }
        if (run.bold && !headingTag) {
          value = `<strong>${value}</strong>`;
        }
        html += value;
      }
      html += `</${tag}>`;
    }
    return html;
  }

  private confirmDeleteNote(): void {
    if (this.note === null || this.note.noteId === 'root') {
      this.notify('根笔记不能删除');
      return;
    }
    const title: string = this.note.title;
    AlertDialog.show({
      title: '删除笔记',
      message: `确定删除“${title}”吗？此操作会同步删除服务器上的笔记。`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: Color.Red,
        action: () => {
          this.deleteCurrentNote();
        }
      }
    });
  }

  private async deleteCurrentNote(): Promise<void> {
    if (this.note === null) return;
    const noteId: string = this.note.noteId;
    const parentId: string = this.note.parentNoteIds.length > 0 ? this.note.parentNoteIds[0] : 'root';
    try {
      const active: AuthSession | null = this.session ?? await this.resolveSession();
      if (active === null) {
        this.notify('登录状态已失效');
        return;
      }
      await EtapiService.deleteNote(active, noteId);
      const context: common.UIAbilityContext | null = this.hostContext();
      if (context !== null) {
        await LocalStore.deleteNote(context, SessionStore.accountKey(), noteId);
      }
      this.notify('笔记已删除');
      this.onDeleted(parentId);
    } catch (error) {
      this.notify('删除失败，请稍后重试');
    }
  }

  private async saveRichEdit(): Promise<void> {
    if (this.isOffline) {
      this.notify('离线缓存为只读，联网后可保存');
      return;
    }
    if (this.note === null || this.session === null || this.isSaving) {
      return;
    }
    if (!this.editingTargetValid() || this.note === null) {
      return;
    }
    const targetId: string = this.note.noteId;
    console.info(`EDIT_SAVE_START target=${targetId} selected=${this.noteId} ` +
      `title=${this.note.title}`);
    const title: string = this.editTitle.trim();
    if (title.length === 0) {
      this.notify('标题不能为空');
      return;
    }
    this.isSaving = true;
    try {
      if (title !== this.note.title) {
        await EtapiService.updateNoteTitle(this.session, targetId, title);
      }
      await EtapiService.updateNoteContent(this.session, targetId, this.serializeRichHtml());
      console.info(`EDIT_SAVE_OK target=${targetId}`);
      this.isRichEditing = false;
      this.richLoaded = false;
      this.notify('已保存到 Trilium');
      await this.loadNote();
    } catch (error) {
      if (error instanceof Error && error.message === 'AUTH_401') {
        this.onSessionExpired();
        this.notify('登录状态已失效');
      } else {
        this.notify('保存失败，请检查网络后重试');
      }
    } finally {
      this.isSaving = false;
    }
  }

  private async saveNote(): Promise<void> {
    if (this.isOffline) {
      this.notify('离线缓存为只读，联网后可保存');
      return;
    }
    if (this.note === null || this.session === null || this.isSaving) {
      return;
    }
    if (!this.editingTargetValid() || this.note === null) {
      return;
    }
    const targetId: string = this.note.noteId;
    console.info(`EDIT_SAVE_START target=${targetId} selected=${this.noteId} ` +
      `title=${this.note.title}`);
    const title: string = this.editTitle.trim();
    if (title.length === 0) {
      this.notify('标题不能为空');
      return;
    }

    this.isSaving = true;
    try {
      if (title !== this.note.title) {
        await EtapiService.updateNoteTitle(this.session, targetId, title);
      }
      await EtapiService.updateNoteContent(this.session, targetId, this.editContent);
      console.info(`EDIT_SAVE_OK target=${targetId}`);
      this.isEditing = false;
      this.notify('已保存到 Trilium');
      await this.loadNote();
    } catch (error) {
      if (error instanceof Error && error.message === 'AUTH_401') {
        this.onSessionExpired();
        this.notify('登录状态已失效');
      } else {
        this.notify('保存失败，请检查网络后重试');
      }
    } finally {
      this.isSaving = false;
    }
  }

  private attributeValue(note: TriliumNote | null, name: string): string {
    if (note === null) {
      return '';
    }
    for (let index: number = 0; index < note.attributes.length; index++) {
      const attribute: EtapiAttributePayload = note.attributes[index];
      if (attribute.type === 'label' && attribute.name === name) {
        return attribute.value ?? '';
      }
    }
    return '';
  }

  private relationRows(): EtapiAttributePayload[] {
    const rows: EtapiAttributePayload[] = [];
    if (this.note === null) {
      return rows;
    }
    for (let index: number = 0; index < this.note.attributes.length; index++) {
      const attribute: EtapiAttributePayload = this.note.attributes[index];
      if (attribute.type === 'relation' && (attribute.value ?? '').length > 0) {
        rows.push(attribute);
      }
    }
    return rows;
  }

  private async loadChildNotes(): Promise<void> {
    if (this.note === null || this.note.childNoteIds.length === 0) {
      this.childNotes = [];
      return;
    }
    const targetId: string = this.note.noteId;
    const context: common.UIAbilityContext | null = this.hostContext();
    if (context === null) {
      return;
    }
    const loaded: TriliumNote[] = [];
    for (let index: number = 0; index < this.note.childNoteIds.length; index++) {
      const childId: string = this.note.childNoteIds[index];
      try {
        const local: LocalNote | null = await LocalStore.get(context,
          SessionStore.accountKey(), childId);
        if (local !== null) {
          loaded.push(local.note);
        }
      } catch (error) {
        // Ignore one missing child; the rest of the list remains usable.
      }
    }
    if (targetId === this.noteId) {
      this.childNotes = loaded;
    }
  }

  private openChildNote(noteId: string): void {
    AppStorage.setOrCreate(StateKeys.SELECTED_NOTE_ID, noteId);
    AppStorage.setOrCreate(StateKeys.SELECTED_NOTE_TITLE, '');
  }

  private colorResource(value: string): string {
    return AttributeVisuals.color(value);
  }

  private pickerColor(): string {
    return AttributeVisuals.hslToHex(this.pickerHue, this.pickerSaturation, this.pickerLightness);
  }

  private iconWallNames(): string[] {
    const names: string[] = Object.keys(BOXICONS_ALL_MAP);
    const query: string = this.iconQuery.trim().toLowerCase();
    if (query.length === 0) {
      return names;
    }
    return names.filter((name: string) => name.toLowerCase().indexOf(query) >= 0);
  }

  private readerSize(base: number): number {
    return Math.round(base * this.readerFontSize / 16);
  }

  private listMarker(block: ContentBlock, index: number): string {
    const level: number = index < block.listLevels.length ? block.listLevels[index] : 0;
    const marker: string = index < block.listMarkers.length ? block.listMarkers[index] : '•';
    if (marker === '•' || marker === '-' || marker === '*' || marker.length === 0) {
      const bullets: string[] = ['•', '◦', '▪', '•'];
      return bullets[Math.min(3, Math.max(0, level))];
    }
    if (/^\d+\.$/.test(marker) && level === 4) {
      return 'a.';
    }
    if (/^\d+\.$/.test(marker) && level >= 5) {
      return 'i.';
    }
    return marker;
  }

  private blockPlainText(block: ContentBlock): string {
    if (block.kind === ContentBlockKind.LIST) {
      return block.listItems.map((item: InlineSegment[], index: number) => {
        const marker: string = index < block.listMarkers.length ? block.listMarkers[index] : '•';
        return `${marker} ${HtmlContentParser.segmentsText(item)}`;
      }).join('\n');
    }
    if (block.kind === ContentBlockKind.HEADING) {
      return HtmlContentParser.segmentsText(block.segments);
    }
    return HtmlContentParser.segmentsText(block.segments);
  }

  private schemaFor(name: string): AttributeSchema | null {
    for (let index: number = 0; index < ATTRIBUTE_SCHEMAS.length; index++) {
      if (ATTRIBUTE_SCHEMAS[index].name === name) {
        return ATTRIBUTE_SCHEMAS[index];
      }
    }
    return null;
  }

  private openAttributePicker(schema: AttributeSchema, editingId: string,
    currentValue: string = ''): void {
    this.attrMenuOpen = false;
    this.attrPickerMode = schema.mode;
    this.attrPickerName = schema.name;
    this.attrEditingId = editingId;
    this.attrHexColor = '';
    this.attrIconName = '';
    this.iconWallOpen = false;
    this.iconQuery = '';
    if (schema.mode === 'color') {
      const hsl: number[] = AttributeVisuals.hexToHsl(currentValue);
      this.pickerHue = hsl[0];
      this.pickerSaturation = hsl[1];
      this.pickerLightness = hsl[2];
    }
    if (editingId.length > 0) {
      setTimeout(() => {
        try {
          this.attrScroller.scrollEdge(Edge.Bottom);
        } catch (error) {
          // Sheet is still laying out.
        }
      }, 80);
    }
  }

  private async pickAttributeValue(value: string): Promise<void> {
    if (this.session === null || this.note === null || this.attrBusy || this.attrPickerName.length === 0) {
      return;
    }
    this.attrBusy = true;
    const editing: boolean = this.attrEditingId.length > 0;
    try {
      if (this.attrEditingId.length > 0) {
        await EtapiService.updateAttribute(this.session, this.attrEditingId, value);
      } else {
        await EtapiService.addAttribute(this.session, this.note.noteId, 'label',
          this.attrPickerName, value);
      }
      this.attrPickerMode = '';
      this.attrPickerName = '';
      this.attrEditingId = '';
      this.attrHexColor = '';
      this.attrIconName = '';
      await this.refreshAttributes();
      this.notify(editing ? '属性已更新' : '属性已添加');
    } catch (error) {
      this.notify('属性保存失败，请检查网络');
    } finally {
      this.attrBusy = false;
    }
  }

  private openCustomAttribute(): void {
    this.attrMenuOpen = false;
    this.attrPickerMode = 'custom';
    this.attrType = 'label';
    this.attrName = '';
    this.attrValue = '';
  }

  private async addAttributeFromInput(): Promise<void> {
    if (this.session === null || this.note === null || this.attrBusy) {
      return;
    }
    let raw: string = this.attrInput.trim();
    if (raw.length === 0) {
      return;
    }
    let type: string = 'label';
    if (raw.startsWith('~')) {
      type = 'relation';
      raw = raw.substring(1);
    } else if (raw.startsWith('#')) {
      raw = raw.substring(1);
    }
    const equals: number = raw.indexOf('=');
    const name: string = (equals >= 0 ? raw.substring(0, equals) : raw).trim();
    const value: string = equals >= 0 ? raw.substring(equals + 1).trim() : '';
    if (name.length === 0) {
      return;
    }
    this.attrBusy = true;
    try {
      await EtapiService.addAttribute(this.session, this.note.noteId, type, name, value);
      this.attrInput = '';
      await this.refreshAttributes();
      this.notify('属性已添加');
    } catch (error) {
      this.notify('添加属性失败，请检查网络');
    } finally {
      this.attrBusy = false;
    }
  }

  private inheritedAttributeRows(): AttributeRow[] {
    return this.attrRows.filter((row: AttributeRow) => !row.owned);
  }

  private ownedAttributeRows(): AttributeRow[] {
    return this.attrRows.filter((row: AttributeRow) => row.owned);
  }

  private attributeRows(): AttributeRow[] {
    const rows: AttributeRow[] = [];
    if (this.note === null) {
      return rows;
    }
    for (let index: number = 0; index < this.note.attributes.length; index++) {
      const attribute: EtapiAttributePayload = this.note.attributes[index];
      rows.push(new AttributeRow(attribute.attributeId ?? '', attribute.type ?? 'label',
        attribute.name ?? '', attribute.value ?? '',
        attribute.noteId === this.note.noteId));
    }
    return rows;
  }

  private openAttributes(): void {
    if (this.note === null) {
      return;
    }
    this.attrRows = this.attributeRows();
    this.attrType = 'label';
    this.attrName = '';
    this.attrValue = '';
    this.attrMenuOpen = false;
    this.attrInput = '';
    this.attrPickerMode = '';
    this.attrPickerName = '';
    this.attrEditingId = '';
    this.attrHexColor = '';
    this.showAttributes = true;
  }

  private async refreshAttributes(): Promise<void> {
    if (this.session === null || this.note === null) {
      return;
    }
    const note: TriliumNote = await EtapiService.getNote(this.session, this.note.noteId);
    this.note.attributes = note.attributes;
    this.tags = note.visibleLabels();
    this.childViewType = this.attributeValue(note, 'viewType');
    this.noteColor = this.attributeValue(note, 'color');
    this.attrRows = this.attributeRows();
    this.loadChildNotes();
    const context: common.UIAbilityContext | null = this.hostContext();
    if (context !== null) {
      await LocalStore.updateAttributes(context, SessionStore.accountKey(),
        note.noteId, note.attributes);
    }
    AppStorage.setOrCreate(SyncService.NOTES_UPDATED_KEY, true);
  }

  private async addAttribute(): Promise<void> {
    if (this.session === null || this.note === null || this.attrBusy ||
      this.attrName.trim().length === 0) {
      return;
    }
    this.attrBusy = true;
    try {
      await EtapiService.addAttribute(this.session, this.note.noteId, this.attrType,
        this.attrName.trim(), this.attrValue);
      this.attrName = '';
      this.attrValue = '';
      this.attrPickerMode = '';
      await this.refreshAttributes();
      this.notify('属性已添加');
    } catch (error) {
      this.notify('添加属性失败，请检查网络');
    } finally {
      this.attrBusy = false;
    }
  }

  private async saveAttribute(row: AttributeRow): Promise<void> {
    if (this.session === null || row.attributeId.length === 0 || this.attrBusy) {
      return;
    }
    this.attrBusy = true;
    try {
      await EtapiService.updateAttribute(this.session, row.attributeId, row.value);
      await this.refreshAttributes();
      this.notify('属性已更新');
    } catch (error) {
      this.notify('更新属性失败，请检查网络');
    } finally {
      this.attrBusy = false;
    }
  }

  private async deleteAttribute(row: AttributeRow): Promise<void> {
    if (this.session === null || row.attributeId.length === 0 || this.attrBusy) {
      return;
    }
    this.attrBusy = true;
    console.info(`ATTR_DELETE_START id=${row.attributeId} name=${row.name}`);
    try {
      await EtapiService.deleteAttribute(this.session, row.attributeId);
      console.info(`ATTR_DELETE_OK id=${row.attributeId}`);
      await this.refreshAttributes();
      this.notify('属性已删除');
    } catch (error) {
      console.error(`ATTR_DELETE_FAILED ${error instanceof Error ? error.message : 'unknown'}`);
      this.notify('删除属性失败，继承属性需在源笔记删除');
    } finally {
      this.attrBusy = false;
    }
  }

  @Builder
  private ChildNotesSection() {
    if (this.note !== null && this.childNotes.length > 0 &&
      (this.childViewType === 'list' || this.childViewType === 'grid')) {
      Column({ space: 10 }) {
        Text(this.childViewType === 'grid' ? '子笔记 · 网格' : '子笔记 · 列表')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(this.childNotes, (child: TriliumNote) => {
            Column({ space: 4 }) {
              Text(child.title)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.childTypeLabel(child))
                .fontSize(10.5)
                .fontColor($r('app.color.text_tertiary'))
            }
            .alignItems(HorizontalAlign.Start)
            .width(this.childViewType === 'grid' ? '48%' : '100%')
            .padding(12)
            .margin({ bottom: 8 })
            .backgroundColor($r('app.color.bg_surface'))
            .borderRadius(10)
            .border({ width: 1, color: $r('app.color.border') })
            .onClick(() => {
              this.openChildNote(child.noteId);
            })
          }, (child: TriliumNote) => child.noteId)
        }
        .width('100%')
      }
      .width('100%')
      .margin({ top: 24 })
    }
  }

  private childTypeLabel(note: TriliumNote): string {
    if (note.type === 'book') {
      return '目录';
    }
    if (note.type === 'code') {
      return '代码';
    }
    if (note.type === 'spreadsheet') {
      return '表格';
    }
    return '笔记';
  }

  @Builder
  private TagChip(label: string) {
    Text(label)
      .fontSize(11.5)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.primary_text'))
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .backgroundColor($r('app.color.tag_bg'))
      .borderRadius(11)
  }

  private serverUrl(): string {
    return SessionStore.serverUrl();
  }

  private accessToken(): string {
    return SessionStore.token();
  }

  private openLink(href: string): void {
    const target: string = href.trim();
    if (target.startsWith('#fnref')) {
      this.scrollToTop();
      return;
    }
    if (target.startsWith('#fn')) {
      try {
        this.scroller.scrollEdge(Edge.Bottom);
      } catch (error) {
        // The content Scroll may not be mounted.
      }
      return;
    }
    if (TriliumLinkRouter.open(href)) {
      return;
    }
    if (/^(https?:|mailto:)/i.test(href.trim())) {
      this.launchExternalLink(href.trim());
      return;
    }
    this.notify(href.length > 0 ? `外部链接：${href}` : '空链接');
  }

  private async launchExternalLink(href: string): Promise<void> {
    const context: common.UIAbilityContext | null = this.hostContext();
    if (context !== null) {
      const opened: boolean = await ExternalLinkLauncher.open(context, href);
      if (opened) {
        return;
      }
    }
    this.notify(`无法打开外部链接：${href}`);
  }

  private listSegments(item: InlineSegment[]): InlineSegment[] {
    if (item.length === 0) {
      return item;
    }
    const first: InlineSegment = item[0];
    if (first.text.startsWith('☐ ') || first.text.startsWith('☑ ')) {
      const copy: InlineSegment[] = item.slice();
      copy[0] = new InlineSegment(first.text.substring(2).replace(/^\s+/, ''),
        first.bold, first.italic, first.code, first.href, first.color, first.backgroundColor);
      return copy;
    }
    return item;
  }

  @Builder
  private ContentBlockView(block: ContentBlock) {
    if (block.kind === ContentBlockKind.HEADING) {
      Column() {
        InlineTextView({
          segments: block.segments,
          fontSize: this.readerSize(block.level === 1 ? 27 : (block.level === 2 ? 23 : 20)),
          lineHeight: this.readerSize(block.level === 1 ? 36 : 31),
          color: $r('app.color.text_primary'),
          weight: FontWeight.Medium,
          onLink: (href: string) => {
            this.openLink(href);
          }
        })
      }
      .width('100%')
      .margin({ top: 7, bottom: 1 })
    } else if (block.kind === ContentBlockKind.QUOTE) {
      Stack({ alignContent: Alignment.TopStart }) {
        Text('❝')
          .fontSize(26)
          .fontColor($r('app.color.text_tertiary'))
          .opacity(0.45)
          .margin({ left: 8, top: 2 })
        Text('❞')
          .fontSize(26)
          .fontColor($r('app.color.text_tertiary'))
          .opacity(0.45)
          .align(Alignment.BottomEnd)
          .margin({ right: 8, bottom: 0 })
        Column({ space: 10 }) {
          ForEach(block.quoteBlocks, (quoteBlock: ContentBlock, quoteIndex: number) => {
            this.ContentBlockView(quoteBlock)
          }, (quoteBlock: ContentBlock, quoteIndex: number) => `quote-${quoteIndex}-${quoteBlock.kind}`)
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 12, bottom: 12 })
      }
      .width('100%')
      .backgroundColor($r('app.color.quote_bg'))
      .borderRadius(4)
    } else if (block.kind === ContentBlockKind.LIST) {
      Column({ space: 7 }) {
        ForEach(block.listItems, (item: InlineSegment[], index: number) => {
          Row({ space: 6 }) {
            if (HtmlContentParser.segmentsText(item).startsWith('☐ ') ||
              HtmlContentParser.segmentsText(item).startsWith('☑ ')) {
              Text(HtmlContentParser.segmentsText(item).substring(0, 1))
                .width(24)
                .textAlign(TextAlign.Center)
                .fontSize(17)
                .lineHeight(27)
                .fontColor(HtmlContentParser.segmentsText(item).startsWith('☑') ?
                  $r('app.color.success') : $r('app.color.text_secondary'))
            } else {
              Text(this.listMarker(block, index))
                .width(24)
                .textAlign(TextAlign.Center)
                .fontSize(15.5)
                .lineHeight(27)
                .fontColor($r('app.color.text_secondary'))
            }
            Column() {
              InlineTextView({
                segments: this.listSegments(item),
                fontSize: this.readerSize(16.5),
                lineHeight: this.readerSize(27),
                color: HtmlContentParser.segmentsText(item).startsWith('☑') ?
                  $r('app.color.text_tertiary') : $r('app.color.text_primary'),
                onLink: (href: string) => {
                  this.openLink(href);
                }
              })
            }
            .layoutWeight(1)
          }
          .width('100%')
          .padding({
            left: 2 + (index < block.listLevels.length ? block.listLevels[index] : 0) * 20
          })
          .alignItems(VerticalAlign.Top)
        }, (item: InlineSegment[], index: number) => `${index}-${HtmlContentParser.segmentsText(item)}`)
      }
      .width('100%')
    } else if (block.kind === ContentBlockKind.CODE) {
      if (block.language.toLowerCase() === 'mermaid' &&
        MermaidParser.parse(block.codeLines).nodes.length > 0) {
        MermaidFlowchart({ sourceLines: block.codeLines })
      } else {
        CodeBlock({
          fileName: this.note !== null ? this.note.title : 'snippet',
          language: block.language.length > 0 ? block.language : 'CODE',
          sourceLines: block.codeLines,
          showHeader: !this.markdownPreview,
          showLineNumbers: !this.markdownPreview
        })
      }
    } else if (block.kind === ContentBlockKind.TABLE) {
      if (block.table !== null) {
        TriliumTable({
          table: block.table,
          onLink: (href: string) => {
            this.openLink(href);
          }
        })
      }
    } else if (block.kind === ContentBlockKind.IMAGE) {
      if (block.image !== null) {
        TriliumImage({
          src: block.image.src,
          alt: block.image.alt,
          widthPercent: block.image.widthPercent
        })
      }
    } else if (block.kind === ContentBlockKind.CALLOUT) {
      if (block.callout !== null) {
        TriliumCallout({
          callout: block.callout,
          onLink: (href: string) => {
            this.openLink(href);
          }
        })
      }
    } else if (block.kind === ContentBlockKind.FOOTNOTES) {
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          Text('脚注')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor($r('app.color.primary_soft'))
            .borderRadius(6)
          Text(`${block.footnotes.length}`)
            .fontSize(10.5)
            .fontColor($r('app.color.text_tertiary'))
          Blank()
        }
        .width('100%')

        Divider()
          .color($r('app.color.border'))
          .strokeWidth(1)

        ForEach(block.footnotes, (item: FootnoteItem, index: number) => {
          Row({ space: 6 }) {
            Text(`${index + 1}.`)
              .fontSize(11.5)
              .fontColor($r('app.color.text_secondary'))
              .width(24)
              .textAlign(TextAlign.End)
            Text('^')
              .fontSize(11)
              .baselineOffset(4)
              .fontColor($r('app.color.primary'))
              .width(14)
              .textAlign(TextAlign.Center)
              .onClick(() => {
                if (item.backHref.length > 0) {
                  this.openLink(item.backHref);
                }
              })
            Text(item.content)
              .fontSize(14)
              .lineHeight(23)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
              .textAlign(TextAlign.Start)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .padding({ top: 1, bottom: 1 })
        }, (item: FootnoteItem, index: number) => `${index}-${item.content}`)
      }
      .width('100%')
      .padding(14)
      .margin({ top: 12, bottom: 12 })
      .backgroundColor($r('app.color.bg_secondary'))
      .border({ width: 1, color: $r('app.color.border') })
      .borderRadius(10)
    } else if (block.kind === ContentBlockKind.PAGE_BREAK) {
      Row({ space: 8 }) {
        Divider()
          .layoutWeight(1)
          .color($r('app.color.border'))
          .strokeWidth(1)
        Text('分页符')
          .fontSize(10.5)
          .fontColor($r('app.color.text_tertiary'))
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .border({ width: 1, color: $r('app.color.border') })
          .borderRadius(4)
          .backgroundColor($r('app.color.bg_primary'))
        Divider()
          .layoutWeight(1)
          .color($r('app.color.border'))
          .strokeWidth(1)
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })
    } else if (block.kind === ContentBlockKind.COLLAPSIBLE) {
      if (block.collapsible !== null) {
        TriliumCollapsible({
          collapsible: block.collapsible,
          onLink: (href: string) => {
            this.openLink(href);
          }
        })
      }
    } else if (block.kind === ContentBlockKind.LINK_EMBED) {
      if (block.linkEmbed !== null) {
        Row({ space: 12 }) {
          Row() {
            AppIcon({
              icon: $r('app.media.ic_doc'),
              iconSize: 20,
              tint: $r('app.color.primary')
            })
          }
          .width(44)
          .height(44)
          .borderRadius(10)
          .backgroundColor($r('app.color.primary_soft'))
          .justifyContent(FlexAlign.Center)

          Column({ space: 4 }) {
            Text(block.linkEmbed.title.length > 0 ? block.linkEmbed.title : block.linkEmbed.url)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(block.linkEmbed.url)
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding(12)
        .margin({ top: 8, bottom: 8 })
        .backgroundColor($r('app.color.bg_secondary'))
        .border({ width: 1, color: $r('app.color.border') })
        .borderRadius(12)
        .onClick(() => {
          if (block.linkEmbed !== null) {
            this.openLink(block.linkEmbed.url);
          }
        })
      }
    } else if (block.kind === ContentBlockKind.INCLUDE) {
      if (block.include !== null) {
        TriliumIncludeNote({
          noteId: block.include.noteId,
          boxSize: block.include.boxSize,
          block: block.include.block,
          onOpen: (noteId: string) => {
            this.openLink(`#root/${noteId}`);
          }
        })
      }
    } else {
      Column() {
        InlineTextView({
          segments: block.segments,
          fontSize: this.readerSize(17),
          lineHeight: this.readerSize(28),
          color: $r('app.color.text_primary'),
          onLink: (href: string) => {
            this.openLink(href);
          }
        })
      }
      .width('100%')
      .padding({ left: block.indent })
    }
  }

  @Builder
  private EmptyState() {
    Column({ space: 14 }) {
      LogoMark({ markSize: 48, showGlow: false })
      Text('选择一篇笔记')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text('左侧目录已连接 Trilium，点击任意笔记开始阅读或编辑。')
        .fontSize(13)
        .lineHeight(21)
        .fontColor($r('app.color.text_tertiary'))
        .textAlign(TextAlign.Center)
        .constraintSize({ maxWidth: 300 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: 36, right: 36, bottom: 80 })
  }

  @Builder
  private NoteHeader(showTitle: boolean) {
    if (showTitle) {
      Text(this.note !== null ? this.note.title : '')
        .fontSize(27)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.noteColor.length > 0
          ? this.colorResource(this.noteColor) : $r('app.color.text_primary'))
        .letterSpacing(0.1)
        .width('100%')
    }

    Row({ space: 8 }) {
      if (this.noteColor.length > 0) {
        Row()
          .width(9)
          .height(28)
          .backgroundColor(this.colorResource(this.noteColor))
          .borderRadius(5)
      }

      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.tags, (label: string) => {
            this.TagChip(label)
          }, (label: string) => label)

          ForEach(this.relationRows(), (relation: EtapiAttributePayload) => {
            Text(`~${relation.name ?? ''}`)
              .fontSize(11.5)
              .fontColor($r('app.color.primary'))
              .padding({ left: 9, right: 9, top: 4, bottom: 4 })
              .border({ width: 1, color: $r('app.color.primary') })
              .borderRadius(11)
              .onClick(() => {
                this.openChildNote(relation.value ?? '');
              })
          }, (relation: EtapiAttributePayload) => relation.attributeId ?? '')

          if (this.tags.length === 0 && this.relationRows().length === 0) {
            this.TagChip(`#${this.typeLabel()}`)
          }
        }
      }
      .layoutWeight(1)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)

      if (this.note !== null) {
        Text('属性')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .onClick(() => {
            this.openAttributes();
          })
      }

      if (this.isEditable()) {
        Text(this.isEditing || this.isRichEditing ? '取消编辑' : '编辑')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .padding({ left: 8, right: 4, top: 4, bottom: 4 })
          .onClick(() => {
            this.toggleEdit();
          })
      }
    }
    .width('100%')
    .margin({ top: 14 })

    Row({ space: 6 }) {
      Text(this.modifiedLabel)
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
      Text('•')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
      Text(this.isSpreadsheet ? '只读' : `${this.formatWordCount(this.wordCount)} 字`)
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
      Text('•')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
      Text(this.typeLabel())
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
      Text('•')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
      if (this.isOffline) {
        Row()
          .width(5)
          .height(5)
          .borderRadius(3)
          .backgroundColor($r('app.color.warning'))
          .margin({ left: 2 })
        Text(`离线缓存 · ${this.offlineLabel}`)
          .fontSize(12)
          .fontColor($r('app.color.warning'))
      } else {
        Row()
          .width(5)
          .height(5)
          .borderRadius(3)
          .backgroundColor($r('app.color.success'))
          .margin({ left: 2 })
        Text('已同步')
          .fontSize(12)
          .fontColor($r('app.color.primary_text'))
      }
    }
    .width('100%')
    .margin({ top: 12 })

    if (this.isOffline) {
      Row({ space: 8 }) {
        AppIcon({
          icon: $r('app.media.ic_clock'),
          iconSize: 15,
          tint: $r('app.color.warning')
        })
        Column({ space: 2 }) {
          Text('离线阅读')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.warning'))
          Text(`显示 ${this.offlineLabel} 缓存的本地副本，图片和编辑不可用`)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .margin({ top: 8 })
      .backgroundColor($r('app.color.bg_secondary'))
      .border({ width: { left: 2 }, color: $r('app.color.warning') })
      .borderRadius(8)
    }
  }

  @Builder
  private EditSurface() {
    Column({ space: 12 }) {
      Row() {
        Text('编辑模式')
          .fontSize(10.5)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .letterSpacing(1)
        Blank()
        if (this.isSimpleContent()) {
          Text('轻编辑')
            .fontSize(11)
            .fontColor($r('app.color.primary_text'))
            .padding({ left: 10, right: 10, top: 3, bottom: 3 })
            .backgroundColor($r('app.color.primary_soft'))
            .borderRadius(10)
            .margin({ right: 8 })
            .onClick(() => {
              this.enterRichEdit();
            })
        }
        Text(this.isSaving ? '保存中…' : '原始内容')
          .fontSize(10.5)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')

      TextInput({ text: this.editTitle, placeholder: '笔记标题' })
        .fontSize(23)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor(Color.Transparent)
        .padding({ left: 0, right: 0 })
        .onChange((value: string) => {
          this.editTitle = value;
        })

      Row({ space: 10 }) {
        Button('取消')
          .type(ButtonType.Capsule)
          .height(36)
          .fontSize(13)
          .backgroundColor($r('app.color.bg_input'))
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
          .onClick(() => {
            this.cancelEdit();
          })
        Button(this.isSaving ? '保存中…' : '保存到 Trilium')
          .type(ButtonType.Capsule)
          .height(36)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .backgroundColor($r('app.color.primary'))
          .fontColor($r('app.color.text_on_primary'))
          .layoutWeight(2)
          .enabled(!this.isSaving)
          .onClick(() => {
            this.saveNote();
          })
      }
      .width('100%')

      TextArea({ text: this.editContent, placeholder: '正文内容' })
        .fontSize(this.note !== null && this.note.type === 'code' ? 13 : 12.5)
        .fontFamily('monospace')
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.bg_secondary'))
        .borderRadius(12)
        .border({ width: 1, color: $r('app.color.border') })
        .padding(12)
        .width('100%')
        .height(360)
        .onChange((value: string) => {
          this.editContent = value;
        })

      Text(this.note !== null && this.note.type === 'code'
        ? '代码笔记按源文本保存，不会插入额外格式。'
        : '文本笔记按 HTML 源码保存，避免丢失已有格式。')
        .fontSize(10.5)
        .lineHeight(17)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private RichFormatButton(label: string, kind: string, bold: boolean) {
    Text(label)
      .fontSize(14)
      .fontWeight(bold ? FontWeight.Bold : FontWeight.Normal)
      .fontColor($r('app.color.text_primary'))
      .width(38)
      .height(32)
      .textAlign(TextAlign.Center)
      .backgroundColor($r('app.color.bg_input'))
      .borderRadius(8)
      .onClick(() => {
        this.applyRichStyle(kind);
      })
  }

  @Builder
  private RichEditSurface() {
    Column({ space: 10 }) {
      Row({ space: 6 }) {
        Text('轻编辑')
          .fontSize(10.5)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .letterSpacing(1)
        Blank()
        Text('源码')
          .fontSize(11)
          .fontColor($r('app.color.primary_text'))
          .padding({ left: 10, right: 10, top: 3, bottom: 3 })
          .backgroundColor($r('app.color.primary_soft'))
          .borderRadius(10)
          .onClick(() => {
            this.enterSourceEdit();
          })
      }
      .width('100%')

      TextInput({ text: this.editTitle, placeholder: '笔记标题' })
        .fontSize(23)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor(Color.Transparent)
        .padding({ left: 0, right: 0 })
        .onChange((value: string) => {
          this.editTitle = value;
        })

      RichEditor({ controller: this.richController })
        .width('100%')
        .height(360)
        .backgroundColor($r('app.color.bg_secondary'))
        .borderRadius(12)
        .border({ width: 1, color: $r('app.color.border') })
        .padding(10)
        .placeholder('开始输入…', {
          fontColor: $r('app.color.text_tertiary')
        })
        .onReady(() => {
          this.loadRichContent();
        })
    }
    .width('100%')
    .padding({ bottom: 100 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private AttributeRowView(row: AttributeRow) {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        Text(`${row.type === 'relation' ? '~' : '#'}${row.name}`)
          .fontSize(12.5)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        if (row.value.length > 0) {
          Text(`=${row.value}`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        } else {
          Blank()
        }
        if (row.owned && row.attributeId.length > 0) {
          if (this.schemaFor(row.name) !== null) {
            Text('选择')
              .fontSize(11)
              .fontColor($r('app.color.primary'))
              .onClick(() => {
                const schema = this.schemaFor(row.name);
                if (schema !== null) {
                  this.openAttributePicker(schema, row.attributeId, row.value);
                }
              })
          }
          Text('×')
            .fontSize(16)
            .fontColor($r('app.color.danger'))
            .padding({ left: 6, right: 2 })
            .onClick(() => {
              this.deleteAttribute(row);
            })
        } else {
          Text('继承')
            .fontSize(10.5)
            .fontColor($r('app.color.text_tertiary'))
        }
      }
      .width('100%')

      if (this.attrEditingId === row.attributeId && this.attrPickerMode.length > 0) {
        this.AttributePicker()
      } else if (this.schemaFor(row.name) === null && row.owned) {
        Row({ space: 8 }) {
          TextInput({ text: row.value, placeholder: '属性值' })
            .fontSize(12)
            .height(32)
            .layoutWeight(1)
            .backgroundColor($r('app.color.bg_secondary'))
            .borderRadius(7)
            .onChange((value: string) => {
              row.value = value;
            })
          Text('保存')
            .fontSize(11)
            .fontColor($r('app.color.primary'))
            .onClick(() => {
              this.saveAttribute(row);
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ top: 7, bottom: 7 })
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
  }

  @Builder
  private AttributePicker() {
    Column({ space: 8 }) {
      Row() {
        Text(this.attrPickerMode === 'custom' ? '自定义属性' :
          this.attrPickerName.length > 0 ? `#${this.attrPickerName}` : '选择属性')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text('取消')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => {
            this.attrPickerMode = '';
            this.attrName = '';
            this.attrValue = '';
          })
      }
      .width('100%')

      if (this.attrPickerMode === 'color') {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(['red', 'blue', 'green', 'yellow', 'purple', 'orange'], (color: string) => {
            Row({ space: 5 }) {
              Row()
                .width(14)
                .height(14)
                .backgroundColor(this.colorResource(color))
                .borderRadius(7)
              Text(color)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
            .padding({ left: 8, right: 8, top: 5, bottom: 5 })
            .margin({ right: 6, bottom: 6 })
            .backgroundColor($r('app.color.bg_secondary'))
            .borderRadius(9)
            .onClick(() => {
              this.pickAttributeValue(color);
            })
          }, (color: string) => color)
        }
        .width('100%')
        Row({ space: 8 }) {
          TextInput({ text: this.attrHexColor, placeholder: '#RRGGBB 或 #AARRGGBB' })
            .fontSize(12)
            .height(34)
            .layoutWeight(1)
            .backgroundColor($r('app.color.bg_secondary'))
            .borderRadius(8)
            .onChange((value: string) => {
              this.attrHexColor = value;
            })
          Text('使用')
            .fontSize(11)
            .fontColor($r('app.color.primary'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor($r('app.color.tag_bg'))
            .borderRadius(8)
            .onClick(() => {
              const hex: string = this.attrHexColor.trim();
              if (/^#([0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(hex)) {
                this.pickAttributeValue(hex);
              } else {
                this.notify('请输入合法 Hex 颜色，如 #FF5733');
              }
            })
        }
        .width('100%')

        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Row()
              .width(26)
              .height(26)
              .backgroundColor(this.pickerColor())
              .borderRadius(13)
              .border({ width: 1, color: $r('app.color.border') })
            Text(this.pickerColor())
              .fontSize(12)
              .fontFamily('monospace')
              .fontColor($r('app.color.text_primary'))
            Blank()
            Button('确认使用')
              .type(ButtonType.Capsule)
              .height(30)
              .fontSize(11)
              .backgroundColor($r('app.color.primary'))
              .fontColor($r('app.color.text_on_primary'))
              .onClick(() => {
                this.pickAttributeValue(this.pickerColor());
              })
          }
          .width('100%')

          Row()
            .width('100%')
            .height(10)
            .borderRadius(5)
            .linearGradient({
              angle: 90,
              colors: [
                ['#FF0000', 0.0], ['#FFFF00', 0.17], ['#00FF00', 0.33],
                ['#00FFFF', 0.5], ['#0000FF', 0.67], ['#FF00FF', 0.83],
                ['#FF0000', 1.0]
              ]
            })
          Text(`H ${Math.round(this.pickerHue)}°`)
            .fontSize(10.5)
            .fontColor($r('app.color.text_tertiary'))
          Slider({ value: this.pickerHue, min: 0, max: 360, style: SliderStyle.OutSet })
            .width('100%')
            .selectedColor(this.pickerColor())
            .onChange((value: number) => {
              this.pickerHue = value;
            })
          Row()
            .width('100%')
            .height(8)
            .borderRadius(4)
            .linearGradient({
              angle: 90,
              colors: [['#9A9A9A', 0.0], [this.pickerColor(), 1.0]]
            })
          Text(`S ${Math.round(this.pickerSaturation)}%`)
            .fontSize(10.5)
            .fontColor($r('app.color.text_tertiary'))
          Slider({ value: this.pickerSaturation, min: 0, max: 100, style: SliderStyle.OutSet })
            .width('100%')
            .selectedColor(this.pickerColor())
            .onChange((value: number) => {
              this.pickerSaturation = value;
            })
          Row()
            .width('100%')
            .height(8)
            .borderRadius(4)
            .linearGradient({
              angle: 90,
              colors: [['#000000', 0.0], [this.pickerColor(), 0.5], ['#FFFFFF', 1.0]]
            })
          Text(`L ${Math.round(this.pickerLightness)}%`)
            .fontSize(10.5)
            .fontColor($r('app.color.text_tertiary'))
          Slider({ value: this.pickerLightness, min: 0, max: 100, style: SliderStyle.OutSet })
            .width('100%')
            .selectedColor(this.pickerColor())
            .onChange((value: number) => {
              this.pickerLightness = value;
            })
        }
        .width('100%')
        .padding(10)
        .backgroundColor($r('app.color.bg_secondary'))
        .borderRadius(10)
      } else if (this.attrPickerMode === 'view') {
        Row({ space: 10 }) {
          ForEach(['list', 'grid'], (view: string) => {
            Text(view === 'list' ? 'List 列表' : 'Grid 网格')
              .fontSize(12)
              .fontColor($r('app.color.text_primary'))
              .padding({ left: 18, right: 18, top: 9, bottom: 9 })
              .backgroundColor($r('app.color.bg_secondary'))
              .borderRadius(9)
              .onClick(() => {
                this.pickAttributeValue(view);
              })
          }, (view: string) => view)
        }
        .width('100%')
      } else if (this.attrPickerMode === 'icon') {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(['bx bx-code', 'bx bx-code-alt', 'bx bx-note', 'bx bx-notepad',
            'bx bx-book', 'bx bx-book-open', 'bx bx-calendar', 'bx bx-check',
            'bx bx-folder', 'bx bx-grid-alt', 'bx bx-tag', 'bx bx-lock',
            'bx bx-search', 'bx bx-cog', 'bx bx-server', 'bx bx-sync',
            'bx bx-palette', 'bx bx-user', 'bx bx-time'], (icon: string) => {
            Text(AttributeVisuals.glyph(icon))
              .fontFamily(AttributeVisuals.FONT_FAMILY)
              .fontSize(22)
              .fontColor($r('app.color.primary'))
              .padding({ left: 9, right: 9, top: 6, bottom: 6 })
              .margin({ right: 6, bottom: 6 })
              .backgroundColor($r('app.color.tag_bg'))
              .borderRadius(8)
              .onClick(() => {
                this.pickAttributeValue(icon);
              })
          }, (icon: string) => icon)
        }
        .width('100%')

        Row({ space: 8 }) {
          Text(this.iconWallOpen ? `收起图标墙（${Object.keys(BOXICONS_ALL_MAP).length}）` :
            '浏览全部图标（1600+）')
            .fontSize(11)
            .fontColor($r('app.color.primary'))
            .onClick(() => {
              this.iconWallOpen = !this.iconWallOpen;
            })
          Blank()
        }
        .width('100%')

        if (this.iconWallOpen) {
          TextInput({ text: this.iconQuery, placeholder: '搜索图标，如 alarm / folder' })
            .fontSize(12)
            .height(34)
            .width('100%')
            .backgroundColor($r('app.color.bg_secondary'))
            .borderRadius(8)
            .onChange((value: string) => {
              this.iconQuery = value;
            })
          Scroll() {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.iconWallNames(), (name: string) => {
                Text(BOXICONS_ALL_MAP[name])
                  .fontFamily(AttributeVisuals.FONT_FAMILY)
                  .fontSize(20)
                  .fontColor($r('app.color.primary'))
                  .width(40)
                  .height(40)
                  .textAlign(TextAlign.Center)
                  .margin(3)
                  .backgroundColor($r('app.color.tag_bg'))
                  .borderRadius(8)
                  .onClick(() => {
                    const prefix: string = name.startsWith('bxs-') ? 'bxs' :
                      (name.startsWith('bxl-') ? 'bxl' : 'bx');
                    this.pickAttributeValue(`${prefix} ${name}`);
                  })
              }, (name: string) => name)
            }
            .width('100%')
          }
          .width('100%')
          .height(280)
          .scrollBar(BarState.Auto)
          .backgroundColor($r('app.color.bg_primary'))
          .borderRadius(8)
        }

        Row({ space: 8 }) {
          TextInput({ text: this.attrIconName, placeholder: '任意图标名，如 code / alarm' })
            .fontSize(12)
            .height(34)
            .layoutWeight(1)
            .backgroundColor($r('app.color.bg_secondary'))
            .borderRadius(8)
            .onChange((value: string) => {
              this.attrIconName = value;
            })
          Text(AttributeVisuals.glyph(`bx bx-${this.attrIconName.trim()}`))
            .fontFamily(AttributeVisuals.FONT_FAMILY)
            .fontSize(20)
            .fontColor($r('app.color.primary'))
          Text('使用')
            .fontSize(11)
            .fontColor($r('app.color.primary'))
            .onClick(() => {
              const name: string = this.attrIconName.trim().replace(/^bx-/, '');
              const iconClass: string = `bx bx-${name}`;
              if (name.length > 0 && AttributeVisuals.hasGlyph(iconClass)) {
                this.pickAttributeValue(iconClass);
              } else {
                this.notify('图标不存在，请从图标墙选择');
              }
            })
        }
        .width('100%')
      } else if (this.attrPickerMode === 'status') {
        Row({ space: 8 }) {
          ForEach(['active', 'done', 'archived', 'todo'], (status: string) => {
            Text(status)
              .fontSize(11)
              .fontColor($r('app.color.primary'))
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .backgroundColor($r('app.color.tag_bg'))
              .borderRadius(8)
              .onClick(() => {
                this.pickAttributeValue(status);
              })
          }, (status: string) => status)
        }
        .width('100%')
      } else if (this.attrPickerMode === 'custom') {
        Row({ space: 8 }) {
          Text(this.attrType === 'relation' ? '~ Relation' : '# Label')
            .fontSize(11)
            .fontColor($r('app.color.primary_text'))
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .backgroundColor($r('app.color.tag_bg'))
            .borderRadius(9)
            .onClick(() => {
              this.attrType = this.attrType === 'relation' ? 'label' : 'relation';
            })
          TextInput({ text: this.attrName, placeholder: 'name' })
            .fontSize(12)
            .height(34)
            .layoutWeight(1)
            .backgroundColor($r('app.color.bg_secondary'))
            .borderRadius(8)
            .onChange((value: string) => {
              this.attrName = value;
            })
        }
        .width('100%')
        Row({ space: 8 }) {
          TextInput({ text: this.attrValue, placeholder: 'value（可空）' })
            .fontSize(12)
            .height(34)
            .layoutWeight(1)
            .backgroundColor($r('app.color.bg_secondary'))
            .borderRadius(8)
            .onChange((value: string) => {
              this.attrValue = value;
            })
          Button('添加')
            .type(ButtonType.Capsule)
            .height(34)
            .fontSize(11.5)
            .backgroundColor($r('app.color.primary'))
            .fontColor($r('app.color.text_on_primary'))
            .onClick(() => {
              this.addAttribute();
            })
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  private AttributeSheet() {
    Column({ space: 10 }) {
      Row() {
        Text('笔记属性')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text('关闭')
          .fontSize(12)
          .fontColor($r('app.color.primary'))
          .onClick(() => {
            this.showAttributes = false;
          })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 12, bottom: 8 })

      Scroll(this.attrScroller) {
        Column({ space: 8 }) {
          Row({ space: 6 }) {
            Text('继承的属性')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
            if (this.inheritedAttributeRows().length === 0) {
              Text('无')
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
            } else {
              ForEach(this.inheritedAttributeRows(), (row: AttributeRow) => {
                Text(`${row.type === 'relation' ? '~' : '#'}${row.name}` +
                  `${row.value.length > 0 ? '=' + row.value : ''}`)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
              }, (row: AttributeRow) => `inherited-${row.attributeId}-${row.name}`)
            }
            Blank()
          }
          .width('100%')
          .padding({ top: 2, bottom: 4 })

          ForEach(this.ownedAttributeRows(), (row: AttributeRow) => {
            this.AttributeRowView(row)
          }, (row: AttributeRow) => `${row.attributeId}-${row.name}`)
        }
        .width('100%')
        .padding({ left: 18, right: 18 })
      }
      .width('100%')
      .constraintSize({ maxHeight: 330 })
      .scrollBar(BarState.Off)

      Column({ space: 8 }) {
        if (this.attrPickerMode.length > 0 && this.attrEditingId.length === 0) {
          this.AttributePicker()
        } else if (this.attrMenuOpen) {
          ForEach(ATTRIBUTE_SCHEMAS, (schema: AttributeSchema) => {
            Row({ space: 8 }) {
              Text(schema.label)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text(`#${schema.name}`)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
              Blank()
              Text('选择')
                .fontSize(11)
                .fontColor($r('app.color.primary'))
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor($r('app.color.bg_surface'))
            .borderRadius(9)
            .onClick(() => {
              this.openAttributePicker(schema, '');
            })
          }, (schema: AttributeSchema) => schema.name)
          Text('自定义属性')
            .fontSize(12)
            .fontColor($r('app.color.primary'))
            .width('100%')
            .padding({ top: 8, bottom: 4 })
            .onClick(() => {
              this.openCustomAttribute();
            })
        } else {
          Row({ space: 8 }) {
            TextInput({ text: this.attrInput, placeholder: '在此输入标签和关系' })
              .fontSize(12)
              .height(36)
              .layoutWeight(1)
              .backgroundColor($r('app.color.bg_secondary'))
              .borderRadius(8)
              .onChange((value: string) => {
                this.attrInput = value;
              })
            Button('+')
              .type(ButtonType.Circle)
              .width(36)
              .height(36)
              .fontSize(18)
              .backgroundColor($r('app.color.primary'))
              .fontColor($r('app.color.text_on_primary'))
              .onClick(() => {
                this.addAttributeFromInput();
              })
          }
          .width('100%')
          Row() {
            Text('快捷选择属性')
              .fontSize(11)
              .fontColor($r('app.color.primary'))
              .onClick(() => {
                this.attrMenuOpen = true;
              })
            Blank()
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 8, bottom: 20 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }

  @Builder
  private SearchSheet() {
    SearchView({
      onClose: () => {
        this.showSearch = false;
      },
      onSelect: (noteId: string) => {
        this.selectSearchResult(noteId);
      }
    })
  }

  @Builder
  private ActiveSheet() {
    if (this.showAttributes) {
      this.AttributeSheet()
    } else if (this.showSearch) {
      this.SearchSheet()
    } else {
      this.PdfOutlineSheet()
    }
  }

  @Builder
  private PdfOutlineSheet() {
    Column() {
      Row() {
        Text('目录')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text('回到开头')
          .fontSize(12)
          .fontColor($r('app.color.primary'))
          .margin({ right: 16 })
          .onClick(() => {
            this.jumpToPdfPage(0);
            this.pdfOutlineOpen = false;
          })
        Text('关闭')
          .fontSize(12)
          .fontColor($r('app.color.primary'))
          .onClick(() => {
            this.pdfOutlineOpen = false;
          })
      }
      .width('100%')
      .height(48)

      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'))

      Scroll() {
        Column({ space: 6 }) {
          if (this.pdfOutlineTitles.length > 0) {
            ForEach(this.pdfOutlineTitles, (title: string, index: number) => {
              Row() {
                Text(title)
                  .fontSize(13)
                  .fontColor(this.pdfOutlinePages[index] === this.pdfJumpPage
                    ? $r('app.color.primary') : $r('app.color.text_primary'))
                  .maxLines(2)
                  .layoutWeight(1)
                Text(`${this.pdfOutlinePages[index] + 1}`)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .padding({ left: 10, right: 10, top: 10, bottom: 10 })
              .borderRadius(8)
              .backgroundColor($r('app.color.bg_secondary'))
              .onClick(() => {
                this.jumpToPdfPage(this.pdfOutlinePages[index]);
                this.pdfOutlineOpen = false;
              })
            }, (title: string, index: number) => `pdf-sheet-${index}-${title}`)
          } else if (this.pdfPageCount > 0) {
            ForEach(this.pdfOutlineFallbackPages(), (pageIndex: number) => {
              Row() {
                Text(`第 ${pageIndex + 1} 页`)
                  .fontSize(13)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)
                Text(`${pageIndex + 1}`)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .height(40)
              .padding({ left: 10, right: 10 })
              .borderRadius(8)
              .backgroundColor($r('app.color.bg_secondary'))
              .onClick(() => {
                this.jumpToPdfPage(pageIndex);
                this.pdfOutlineOpen = false;
              })
            }, (pageIndex: number) => `pdf-sheet-page-${pageIndex}`)
          } else {
            Text('目录加载中…')
              .fontSize(13)
              .fontColor($r('app.color.text_tertiary'))
              .padding({ top: 18, bottom: 18 })
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 22, right: 22, top: 8, bottom: 22 })
    .backgroundColor($r('app.color.bg_primary'))
  }

  private pdfOutlineFallbackPages(): number[] {
    const pages: number[] = [];
    const max: number = Math.min(this.pdfPageCount, 200);
    for (let i: number = 0; i < max; i++) {
      pages.push(i);
    }
    return pages;
  }

  @Builder
  private SheetTabOverlay() {
    Row() {
      Scroll() {
        Row() {
          ForEach(this.sheetNames, (name: string, index: number) => {
            Row() {
              Text(name)
                .fontSize(13)
                .fontWeight(this.activeSheet === index ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(this.activeSheet === index ? $r('app.color.primary') : $r('app.color.text_secondary'))
                .maxLines(1)
            }
            .height(50)
            .padding({ left: 18, right: 18 })
            .justifyContent(FlexAlign.Center)
            .backgroundColor(this.activeSheet === index ? $r('app.color.bg_surface') : $r('app.color.bg_secondary'))
            .border({
              width: { bottom: this.activeSheet === index ? 3 : 0 },
              color: $r('app.color.primary')
            })
            .onClick(() => {
              this.activeSheet = index;
            })
          }, (name: string, index: number) => `sheet-overlay-${index}-${name}`)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .layoutWeight(1)
    }
    .width('100%')
    .height(50)
    .backgroundColor($r('app.color.bg_secondary'))
    .border({ width: { top: 1 }, color: $r('app.color.border') })
    .position({ x: 0, y: '100%' })
    .markAnchor({ x: 0, y: '100%' })
    .zIndex(20)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        TopNavigationBar({
          crumbs: this.breadcrumbCrumbs(),
          activeCrumb: this.breadcrumbActive(),
          showOutline: this.isPdf && this.note !== null && !this.isLoading &&
            this.errorMessage.length === 0,
          loading: this.pdfJumping,
          onMenu: this.onMenu,
          onSearch: () => {
            this.openSearch();
          },
          onMore: this.onMore,
          onDelete: () => {
            this.confirmDeleteNote();
          },
          onOutline: () => {
            this.showSearch = false;
            this.pdfOutlineRequest++;
            this.pdfOutlineOpen = true;
          },
          onTitle: () => {
            this.returnToNoteStart();
          }
        })

        if (this.isPdf && this.note !== null && !this.isLoading &&
          this.errorMessage.length === 0 && !this.isEditing) {
          Stack({ alignContent: Alignment.TopStart }) {
            ForEach([this.pdfViewerEpoch], (epoch: number) => {
              PdfViewer({
                sourceBuffer: this.pdfBuffer,
                sourcePath: this.pdfPath,
                jumpPage: this.pdfJumpPage,
                outlineRequest: this.pdfOutlineRequest,
                onScrollChange: (offsetPixels: number) => {
                  this.onPdfScroll(offsetPixels);
                },
                onPageChanged: (pageIndex: number) => {
                  this.onPdfPageChanged(pageIndex);
                },
                onOutlineReady: (titles: string[], pages: number[], count: number) => {
                  this.pdfOutlineTitles = titles;
                  this.pdfOutlinePages = pages;
                  this.pdfPageCount = count;
                }
              })
                .width('100%')
                .height('100%')
                .translate({
                  y: this.pdfHeaderHeight * (1 - this.pdfScrollProgress)
                })
            }, (epoch: number) => `pdf-viewer-${epoch}`)

            Column() {
              this.NoteHeader(true)
              Divider()
                .strokeWidth(1)
                .color($r('app.color.divider'))
                .margin({ top: 18, bottom: 18 })
            }
            .width('100%')
            .backgroundColor($r('app.color.bg_primary'))
            .zIndex(10)
            .position({ x: 0, y: 0 })
            .translate({ y: -this.pdfHeaderHeight * this.pdfScrollProgress })
            .onAreaChange((oldArea: Area, newArea: Area) => {
              const heightValue: number = parseFloat(newArea.height.toString());
              if (!isNaN(heightValue) && heightValue > 40) {
                this.pdfHeaderHeight = heightValue;
              }
            })
          }
          .width('100%')
          .layoutWeight(1)
          .clip(true)
          .padding({ left: 22, right: 22 })
        } else {
          Scroll(this.scroller) {
          Column() {
            Column() {
              if (this.isLoading) {
                Column({ space: 12 }) {
                  LoadingProgress()
                    .width(26)
                    .height(26)
                    .color($r('app.color.primary'))
                  Text('正在读取笔记…')
                    .fontSize(12.5)
                    .fontColor($r('app.color.text_tertiary'))
                }
                .width('100%')
                .height(320)
                .justifyContent(FlexAlign.Center)
              } else if (this.errorMessage.length > 0) {
                Column({ space: 12 }) {
                  Text(this.errorMessage)
                    .fontSize(13)
                    .fontColor($r('app.color.danger'))
                  Button('重试')
                    .type(ButtonType.Capsule)
                    .height(34)
                    .fontSize(13)
                    .backgroundColor($r('app.color.primary_soft'))
                    .fontColor($r('app.color.primary_text'))
                    .onClick(() => {
                      this.loadNote();
                    })
                }
                .width('100%')
                .height(260)
                .justifyContent(FlexAlign.Center)
              } else if (this.note === null) {
                this.EmptyState()
              } else if (this.isRichEditing) {
                this.NoteHeader(false)
                Divider()
                  .strokeWidth(1)
                  .color($r('app.color.divider'))
                  .margin({ top: 18, bottom: 18 })
                this.RichEditSurface()
              } else if (this.isEditing) {
                this.NoteHeader(false)
                Divider()
                  .strokeWidth(1)
                  .color($r('app.color.divider'))
                  .margin({ top: 18, bottom: 18 })
                this.EditSurface()
              } else {
                Column({ space: 0 }) {
                  this.NoteHeader(true)
                  Divider()
                    .strokeWidth(1)
                    .color($r('app.color.divider'))
                    .margin({ top: 18, bottom: 18 })
                }
                .width('100%')
                .padding({
                  left: this.isSpreadsheet ? 22 : 0,
                  right: this.isSpreadsheet ? 22 : 0
                })

                if (this.note.isProtected) {
                  Row({ space: 8 }) {
                    AppIcon({
                      icon: $r('app.media.ic_lock'),
                      iconSize: 15,
                      tint: $r('app.color.text_secondary')
                    })
                    Text('受保护笔记，ETAPI 不提供正文读取。')
                      .fontSize(13)
                      .fontColor($r('app.color.text_secondary'))
                  }
                  .padding(14)
                  .backgroundColor($r('app.color.bg_secondary'))
                  .borderRadius(12)
                } else if ((this.note.type === 'image' || this.note.type === 'file') && !this.isPdf) {
                  Text('该笔记是图片/文件类型，当前版本暂不支持内容预览。')
                    .fontSize(13)
                    .lineHeight(22)
                    .fontColor($r('app.color.text_secondary'))
                } else if (this.isPdf) {
                  PdfViewer({
                    sourceBuffer: this.pdfBuffer,
                    sourcePath: this.pdfPath
                  })
                  .width('100%')
                  .height(620)
                  .margin({ left: -22, right: -22 })
                } else if (this.isSpreadsheet) {
                  ForEach([this.activeSheet], (sheetIndex: number) => {
                    NativeSheetView({
                      content: this.spreadsheetContent,
                      noteId: this.note !== null ? this.note.noteId : '',
                      sheetIndex: sheetIndex
                    })
                    .width('100%')
                    .margin({ left: 0, right: 0 })
                  }, (sheetIndex: number) => `native-sheet-${sheetIndex}`)
                } else if (this.note.type !== 'text' && this.note.type !== 'code' && this.note.type !== 'book') {
                  Text(`暂不支持该文件类型（type: ${this.note.type}, mime: ${this.note.mime}）`)
                    .fontSize(13)
                    .lineHeight(22)
                    .fontColor($r('app.color.text_secondary'))
                } else if (this.blocks.length === 0) {
                  Text('这篇笔记还没有正文。')
                    .fontSize(14)
                    .fontColor($r('app.color.text_tertiary'))
                    .margin({ top: 8 })
                } else {
                  Column({ space: 18 }) {
                    ForEach(this.blocks, (block: ContentBlock, index: number) => {
                      this.ContentBlockView(block)
                    }, (block: ContentBlock, index: number) => `${block.kind}-${index}`)
                  }
                  .width('100%')
                }
                this.ChildNotesSection()
              }
            }
            .width('100%')
            .constraintSize({ maxWidth: this.isSpreadsheet ? 2400 : 760 })
            .padding({
              left: this.isSpreadsheet ? 0 : 22,
              right: this.isSpreadsheet ? 0 : 22,
              top: 18,
              bottom: 142
            })
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .onAreaChange((oldArea: Area, newArea: Area) => {
            const contentHeight: number = parseFloat(newArea.height.toString());
            if (!isNaN(contentHeight) && contentHeight > 0) {
              this.readingContentHeight = contentHeight;
              this.updateReadingProgress(this.lastReadingOffset);
            }
          })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
        .align(Alignment.Top)
        .onAreaChange((oldArea: Area, newArea: Area) => {
          const viewportHeight: number = parseFloat(newArea.height.toString());
          if (!isNaN(viewportHeight) && viewportHeight > 0) {
            this.readingViewportHeight = viewportHeight;
            this.updateReadingProgress(this.lastReadingOffset);
          }
        })
        .onDidScroll((xOffset: number, yOffset: number, scrollState: ScrollState) => {
          if (this.isRestoringScroll || this.loadedNoteId.length === 0) {
            return;
          }
          try {
            const offset: OffsetResult = this.scroller.currentOffset();
            ReadingPositionStore.save(this.loadedNoteId, offset.yOffset);
            this.updateReadingProgress(offset.yOffset);
          } catch (error) {
            // The Scroll component may be transitioning between notes.
          }
        })
        .onTouch((event: TouchEvent) => {
          const touch: TouchObject | undefined = event.touches[0];
          if (touch === undefined) {
            return;
          }
          if (event.type === TouchType.Down) {
            this.swipeStartX = touch.x;
            this.swipeStartY = touch.y;
            this.swipeTracking = true;
          } else if (event.type === TouchType.Up && this.swipeTracking) {
            const dx: number = touch.x - this.swipeStartX;
            const dy: number = touch.y - this.swipeStartY;
            this.swipeTracking = false;
            if (dx > 90 && Math.abs(dy) < 70) {
              this.onSwipeRight();
            }
          } else if (event.type === TouchType.Cancel) {
            this.swipeTracking = false;
          }
        })
        }
      }
      .width('100%')
      .height('100%')

      if (this.note !== null && !this.isLoading && !this.isEditing && !this.isRichEditing &&
        !this.isPdf && this.errorMessage.length === 0 &&
        (this.blocks.length > 0 || this.isSpreadsheet) &&
        this.readingContentHeight > this.readingViewportHeight + 1) {
        Row() {
          Stack({ alignContent: Alignment.Top }) {
            Row()
              .width(5)
              .height('100%')
              .borderRadius(3)
              .backgroundColor($r('app.color.border'))
            Row()
              .width(5)
              .height(`${Math.max(this.readingProgress * 100, 0)}%`)
              .borderRadius(3)
              .backgroundColor($r('app.color.primary'))
          }
          .width(6)
          .height('100%')
        }
        .width(0)
        .height(0)
        .opacity(0)
        .justifyContent(FlexAlign.End)
        .padding({ top: 8, bottom: 12, right: 5 })
        .hitTestBehavior(HitTestMode.None)
        .zIndex(20)
      }

      if (this.note !== null && !this.isSpreadsheet && !this.isPdf &&
        this.errorMessage.length === 0 && (this.isEditing || this.isRichEditing)) {
        Row() {
          FloatingToolbar({
            onAction: (action: string) => {
              this.handleFloatingAction(action);
            },
            onDone: () => {
              if (this.isRichEditing) {
                this.saveRichEdit();
              } else if (this.isEditing) {
                this.saveNote();
              } else {
                this.notify('当前没有未保存的修改');
              }
            }
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .position({ x: 0, y: this.toolbarY })
      }

      if (this.note !== null && this.isSpreadsheet && !this.isEditing &&
        this.sheetNames.length > 1) {
        this.SheetTabOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
    .onClick(() => {
      const tick: number = AppStorage.get<number>('TEXT_SELECTION_DISMISS') ?? 0;
      AppStorage.setOrCreate('TEXT_SELECTION_DISMISS', tick + 1);
      try {
        this.getUIContext().getFocusController().clearFocus();
      } catch (error) {
        // No focus owner.
      }
    })
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const heightValue: number = parseFloat(newArea.height.toString());
      if (!isNaN(heightValue) && heightValue > 120) {
        this.editorViewportHeight = heightValue;
        if (this.keyboardInset <= 0 || this.fullViewportHeight <= 0) {
          this.fullViewportHeight = heightValue;
        }
        this.recomputeToolbarY();
      }
    })
    .bindSheet(this.showSearch || this.pdfOutlineOpen || this.showAttributes, this.ActiveSheet, {
      height: this.showAttributes ? 520 : SheetSize.LARGE,
      dragBar: true,
      showClose: false,
      backgroundColor: $r('app.color.bg_primary'),
      onDisappear: () => {
        this.showSearch = false;
        this.pdfOutlineOpen = false;
        this.showAttributes = false;
      }
    })
  }
}
