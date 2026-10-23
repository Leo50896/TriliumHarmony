import { common } from '@kit.AbilityKit';
import { AppConstants } from '../constants/AppConstants';
import { MockConfig } from '../constants/MockConfig';
import { StateKeys } from '../constants/StateKeys';
import { MIME_ICONS } from '../utils/MimeIcons';
import { AuthSession } from '../models/AuthModels';
import { CachedNote } from '../models/CacheModels';
import {
  createDrawerItems,
  DrawerItem,
  DrawerItemType
} from '../models/UiModels';
import {
  DrawerTreeNode,
  isHiddenNoteId,
  TriliumNote
} from '../models/TriliumModels';
import { EtapiService } from '../services/EtapiService';
import { LocalStore } from '../services/LocalStore';
import { AttributeVisuals } from '../utils/AttributeVisuals';
import { SessionStore } from '../services/SessionStore';
import { SyncResult, SyncService } from '../services/SyncService';
import { AppIcon } from './AppIcon';
import { LogoMark } from './LogoMark';

/**
 * Navigation drawer content. The host screen places it inside a
 * SideBarContainer so drag-to-open, width constraints and overlay behavior are
 * provided by the framework instead of a hand-rolled animation.
 *
 * In real mode the tree is lazy-loaded from ETAPI:
 *   root -> direct children -> children of each expanded folder.
 * Pull-to-refresh re-reads the root and every currently expanded branch.
 */
@Component
export struct SideDrawer {
  @Prop @Watch('onVisibleChanged') visible: boolean = false;
  @StorageProp('auth.token') @Watch('onTokenChanged') private token: string = '';
  @StorageProp('auth.serverUrl') private serverUrl: string = '';
  @StorageLink('nav.selectedNoteId') @Watch('onSelectedNoteChanged') private selectedNoteId: string = '';
  @StorageLink('notesUpdated') @Watch('onNotesUpdated') private notesUpdated: boolean = false;
  @StorageLink('sync.force') @Watch('onForceSync') private forceSync: boolean = false;
  onCloseDrawer: () => void = () => {};
  onOpenGlobalSearch: () => void = () => {};
  onOpenNote: (noteId: string, title: string) => void = () => {};
  onOpenSettings: () => void = () => {};
  onOpenNoteMap: () => void = () => {};
  onNewNote: () => void = () => {};
  onSessionExpired: () => void = () => {};

  @State private searchText: string = '';
  @State private tree: DrawerTreeNode[] = [];
  @State private isSyncing: boolean = false;
  @State private isRefreshing: boolean = false;
  @State private hasSyncError: boolean = false;
  @State private isNetworkOffline: boolean = false;
  @State private syncMessage: string = '正在同步…';
  @State private expandedIds: string[] = [];
  @State private loadingNodeId: string = '';
  @State private loadedNoteCount: number = 0;
  @State private cachedNotes: CachedNote[] = [];

  private session: AuthSession | null = null;
  private noteCache: Map<string, TriliumNote> = new Map();
  private rootChildIds: string[] = [];
  private mockItems: DrawerItem[] = createDrawerItems();
  private didAutoExpand: boolean = false;
  private lastSyncAt: number = 0;

  aboutToAppear(): void {
    this.initialize();
  }

  private async initialize(): Promise<void> {
    this.loadCachedNotes();
    if (MockConfig.USE_MOCK) {
      this.buildMockTree();
      this.syncMessage = 'Mock 模式';
      return;
    }
    await this.loadLocalNotes();
    if (this.noteCache.size > 0) {
      this.lastSyncAt = Date.now();
      this.scheduleBackgroundSync();
    } else {
      this.syncTree(false);
    }
  }

  private scheduleBackgroundSync(): void {
    setTimeout(() => {
      this.backgroundSync();
    }, 1000);
  }

  private async backgroundSync(): Promise<void> {
    if (this.session === null) {
      this.session = SessionStore.currentSession();
    }
    const hostContext: common.Context | undefined = this.getUIContext().getHostContext();
    if (this.session === null || hostContext === undefined) {
      return;
    }
    try {
      const result: SyncResult = await SyncService.sync(hostContext as common.UIAbilityContext,
        this.session, SessionStore.accountKey());
      await this.loadLocalNotes();
      this.lastSyncAt = Date.now();
      this.syncMessage = result.fullSync
        ? `全量 ${result.pulled} 篇 ${this.formatClock(new Date())}`
        : `增量 ${result.pulled} 项 ${this.formatClock(new Date())}`;
    } catch (error) {
      this.hasSyncError = true;
      this.isNetworkOffline = true;
      this.syncMessage = '离线，显示本地库';
      console.error(`UI_SYNC_FAILED ${error instanceof Error ? error.message : 'unknown'}`);
    }
  }

  private async loadLocalNotes(): Promise<void> {
    console.info('UI_LOAD_LOCAL_START');
    const hostContext: common.Context | undefined = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      return;
    }
    try {
      const notes: TriliumNote[] = await LocalStore.all(
        hostContext as common.UIAbilityContext, SessionStore.accountKey());
      if (notes.length === 0) {
        return;
      }
      this.noteCache = new Map();
      const computedChildren: Map<string, string[]> = new Map();
      for (let index: number = 0; index < notes.length; index++) {
        const note: TriliumNote = notes[index];
        if (note.noteId === '3UZWsA8HXqWH') {
          console.info(`UI_ATTR_LOAD id=${note.noteId} attrs=${JSON.stringify(note.attributes)}`);
        }
        this.noteCache.set(note.noteId, note);
        for (let parentIndex: number = 0; parentIndex < note.parentNoteIds.length; parentIndex++) {
          const parentId: string = note.parentNoteIds[parentIndex];
          const children: string[] | undefined = computedChildren.get(parentId);
          if (children === undefined) {
            computedChildren.set(parentId, [note.noteId]);
          } else {
            children.push(note.noteId);
          }
        }
      }
      this.noteCache.forEach((note: TriliumNote) => {
        const children: string[] | undefined = computedChildren.get(note.noteId);
        note.childNoteIds = children !== undefined ? children : [];
        note.childNoteIds.sort((left: string, right: string) => {
          const leftNote: TriliumNote | undefined = this.noteCache.get(left);
          const rightNote: TriliumNote | undefined = this.noteCache.get(right);
          return (leftNote !== undefined ? leftNote.notePosition : 0) -
            (rightNote !== undefined ? rightNote.notePosition : 0);
        });
      });
      const rootChildSet: Set<string> = new Set();
      const root: TriliumNote | undefined = this.noteCache.get('root');
      if (root !== undefined) {
        for (let index: number = 0; index < root.childNoteIds.length; index++) {
          const noteId: string = root.childNoteIds[index];
          if (!isHiddenNoteId(noteId)) {
            rootChildSet.add(noteId);
          }
        }
      }
      this.noteCache.forEach((note: TriliumNote) => {
        if (note.noteId !== 'root' && !isHiddenNoteId(note.noteId) &&
          note.parentNoteIds.indexOf('root') >= 0) {
          rootChildSet.add(note.noteId);
        }
      });
      this.rootChildIds = Array.from(rootChildSet);
      this.rootChildIds.sort((left: string, right: string) => {
        const leftNote: TriliumNote | undefined = this.noteCache.get(left);
        const rightNote: TriliumNote | undefined = this.noteCache.get(right);
        return (leftNote !== undefined ? leftNote.notePosition : 0) -
          (rightNote !== undefined ? rightNote.notePosition : 0);
      });
      this.rebuildTree();
      this.loadedNoteCount = Math.max(0, this.noteCache.size);
      this.syncMessage = `本地库 ${this.noteCache.size} 篇`;
      console.info(`UI_LOAD_LOCAL_DONE notes=${this.noteCache.size} root=${this.rootChildIds.length} ` +
        `tree=${this.tree.length}`);
    } catch (error) {
      console.error(`UI_LOAD_LOCAL_FAILED ${error instanceof Error ? error.message : 'unknown'}`);
    }
  }

  private async loadCachedNotes(): Promise<void> {
    const hostContext: common.Context | undefined = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      return;
    }
    try {
      this.cachedNotes = await LocalStore.recent(
        hostContext as common.UIAbilityContext, SessionStore.accountKey(), 8);
    } catch (error) {
      this.cachedNotes = [];
    }
  }

  private openCachedNote(item: CachedNote): void {
    this.selectedNoteId = item.noteId;
    AppStorage.setOrCreate(StateKeys.SELECTED_NOTE_TITLE, item.title);
    this.onOpenNote(item.noteId, item.title);
    this.onCloseDrawer();
  }

  private formatCachedTime(value: number): string {
    const date: Date = new Date(value);
    const hours: string = date.getHours().toString().padStart(2, '0');
    const minutes: string = date.getMinutes().toString().padStart(2, '0');
    return `${hours}:${minutes}`;
  }

  private onVisibleChanged(): void {
    if (!this.visible || this.isSyncing || MockConfig.USE_MOCK) {
      return;
    }
    if (AppStorage.get<boolean>(StateKeys.EDITOR_EDITING) === true) {
      return;
    }
    if (Date.now() - this.lastSyncAt < 3000) {
      return;
    }
    this.syncTree(false, true);
  }

  private onTokenChanged(): void {
    if (MockConfig.USE_MOCK) {
      return;
    }
    this.session = null;
    if (this.token.length === 0) {
      this.tree = [];
      this.hasSyncError = true;
      this.isNetworkOffline = false;
      this.syncMessage = '鐧诲綍鐘舵€佸凡澶辨晥';
      return;
    }
    this.syncTree(false);
  }

  private onSelectedNoteChanged(): void {
    if (this.tree.length > 0) {
      this.rebuildTree();
    }
    if (AppStorage.get<boolean>(StateKeys.EDITOR_EDITING) !== true &&
      Date.now() - this.lastSyncAt >= 3000) {
      AppStorage.setOrCreate(StateKeys.SYNC_FORCE, true);
    }
  }

  private onNotesUpdated(): void {
    console.info(`UI_NOTES_UPDATED signal=${this.notesUpdated}`);
    if (!this.notesUpdated) {
      return;
    }
    this.notesUpdated = false;
    this.loadLocalNotes();
  }

  private onForceSync(): void {
    if (!this.forceSync) {
      return;
    }
    this.forceSync = false;
    if (AppStorage.get<boolean>(StateKeys.EDITOR_EDITING) === true) {
      return;
    }
    if (Date.now() - this.lastSyncAt < 3000) {
      return;
    }
    this.syncTree(true, true);
  }

  private async syncTree(fromPull: boolean, silent: boolean = false): Promise<void> {
    console.info(`UI_SYNC_START fromPull=${fromPull} silent=${silent} syncing=${this.isSyncing}`);
    if (this.isSyncing) {
      return;
    }
    this.isSyncing = true;
    if (!silent) {
      this.isRefreshing = true;
      this.hasSyncError = false;
      this.isNetworkOffline = false;
      this.syncMessage = '正在同步…';
    }

    try {
      if (MockConfig.USE_MOCK) {
        await this.delay(500);
        this.buildMockTree();
        this.syncMessage = 'Mock 模式';
        return;
      }

      if (this.session === null) {
        this.session = SessionStore.currentSession();
      }
      if (this.session === null) {
        this.hasSyncError = true;
        this.syncMessage = '登录状态已失效';
        this.onSessionExpired();
        return;
      }

      if (this.noteCache.size > 0 && !fromPull) {
        this.scheduleBackgroundSync();
        this.syncMessage = `本地库 ${this.noteCache.size} 篇`;
        return;
      }

      const hostContext: common.Context | undefined = this.getUIContext().getHostContext();
      if (hostContext === undefined) {
        return;
      }
      const result: SyncResult = await SyncService.sync(
        hostContext as common.UIAbilityContext, this.session, SessionStore.accountKey());
      await this.loadLocalNotes();
      this.lastSyncAt = Date.now();
      if (!silent) {
        this.syncMessage = result.fullSync
          ? `全量 ${result.pulled} 篇 ${this.formatClock(new Date())}`
          : `增量 ${result.pulled} 项 ${this.formatClock(new Date())}`;
      }
    } catch (error) {
      this.hasSyncError = true;
      if (error instanceof Error && error.message === 'AUTH_401') {
        this.isNetworkOffline = false;
        this.session = null;
        this.syncMessage = '登录状态已失效';
        this.onSessionExpired();
      } else {
        console.error(`UI_SYNC_TREE_FAILED ${error instanceof Error ? error.message : 'unknown'}`);
        if (!silent) {
          this.isNetworkOffline = true;
          this.syncMessage = '网络不可用，下拉重试';
          this.loadCachedNotes();
        }
      }
    } finally {
      this.isSyncing = false;
      if (!silent) {
        this.isRefreshing = false;
        if (fromPull && this.hasSyncError) {
          this.syncMessage = this.isNetworkOffline ? '网络不可用，下拉重试' : '同步失败，下拉重试';
        }
      }
    }
  }

  private async autoExpandFirstBook(): Promise<void> {
    if (this.session === null) {
      return;
    }
    for (let index: number = 0; index < this.rootChildIds.length; index++) {
      const note: TriliumNote | undefined = this.noteCache.get(this.rootChildIds[index]);
      if (note !== undefined && note.title.includes('知识库') && note.hasVisibleChildren()) {
        this.expandedIds = [note.noteId];
        await this.ensureChildren(note.noteId);
        return;
      }
    }
    for (let index: number = 0; index < this.rootChildIds.length; index++) {
      const note: TriliumNote | undefined = this.noteCache.get(this.rootChildIds[index]);
      if (note !== undefined && note.hasVisibleChildren()) {
        this.expandedIds = [note.noteId];
        await this.ensureChildren(note.noteId);
        return;
      }
    }
  }

  private async ensureChildren(noteId: string): Promise<void> {
    if (this.session === null) {
      return;
    }
    const parent: TriliumNote | undefined = this.noteCache.get(noteId);
    if (parent === undefined) {
      return;
    }
    const missing: string[] = parent.childNoteIds.filter((childId: string) =>
      !isHiddenNoteId(childId) && !this.noteCache.has(childId));
    if (missing.length === 0) {
      return;
    }
    const loaded: TriliumNote[] = await EtapiService.getNotes(this.session, missing);
    for (let index: number = 0; index < loaded.length; index++) {
      this.noteCache.set(loaded[index].noteId, loaded[index]);
    }
    if (this.searchText.trim().length === 0) {
      this.loadedNoteCount = Math.max(0, this.noteCache.size - 1);
    }
  }

  private isExpanded(noteId: string): boolean {
    return this.expandedIds.indexOf(noteId) >= 0;
  }

  private rebuildTree(): void {
    const rows: DrawerTreeNode[] = [];
    const query: string = this.searchText.trim().toLowerCase();

    if (query.length > 0) {
      const matches: TriliumNote[] = [];
      this.noteCache.forEach((note: TriliumNote) => {
        if (note.noteId !== 'root' && !isHiddenNoteId(note.noteId) &&
          note.title.toLowerCase().includes(query)) {
          matches.push(note);
        }
      });
      matches.sort((left: TriliumNote, right: TriliumNote) => {
        if (left.title < right.title) {
          return -1;
        }
        if (left.title > right.title) {
          return 1;
        }
        return 0;
      });
      for (let index: number = 0; index < matches.length; index++) {
        const note: TriliumNote = matches[index];
        rows.push(new DrawerTreeNode(note.noteId, note.title, 0, note.hasVisibleChildren(),
          this.isExpanded(note.noteId), this.selectedNoteId === note.noteId,
          note.type, note.isProtected));
      }
    } else {
      for (let index: number = 0; index < this.rootChildIds.length; index++) {
        this.appendVisible(this.rootChildIds[index], 0, rows);
      }
    }
    this.tree = rows;
    this.loadedNoteCount = query.length > 0 ? rows.length : Math.max(0, this.noteCache.size - 1);
  }

  private appendVisible(noteId: string, level: number, rows: DrawerTreeNode[]): void {
    if (isHiddenNoteId(noteId)) {
      return;
    }
    const note: TriliumNote | undefined = this.noteCache.get(noteId);
    if (note === undefined) {
      return;
    }
    const expanded: boolean = this.isExpanded(note.noteId);
    rows.push(new DrawerTreeNode(note.noteId, note.title, level, note.hasVisibleChildren(),
      expanded, this.selectedNoteId === note.noteId, note.type, note.isProtected));

    if (expanded) {
      for (let index: number = 0; index < note.childNoteIds.length; index++) {
        this.appendVisible(note.childNoteIds[index], level + 1, rows);
      }
    }
  }

  private async handleNodeTap(node: DrawerTreeNode): Promise<void> {
    if (MockConfig.USE_MOCK) {
      this.handleMockTap(node);
      return;
    }
    this.selectedNoteId = node.noteId;
    AppStorage.setOrCreate(StateKeys.SELECTED_NOTE_TITLE, node.title);
    this.rebuildTree();
    this.onOpenNote(node.noteId, node.title);
    this.onCloseDrawer();
  }

  private async toggleNode(node: DrawerTreeNode): Promise<void> {
    if (MockConfig.USE_MOCK) {
      return;
    }
    if (this.isExpanded(node.noteId)) {
      this.removeExpanded(node.noteId);
      this.rebuildTree();
      return;
    }
    if (this.session === null || this.isSyncing) {
      return;
    }
    this.loadingNodeId = node.noteId;
    try {
      await this.ensureChildren(node.noteId);
      if (!this.isExpanded(node.noteId)) {
        this.expandedIds = this.expandedIds.concat([node.noteId]);
      }
      this.rebuildTree();
    } catch (error) {
      this.hasSyncError = true;
      if (error instanceof Error && error.message === 'AUTH_401') {
        this.session = null;
        this.syncMessage = '登录状态已失效';
        this.onSessionExpired();
      } else {
        this.syncMessage = '加载子目录失败';
      }
    } finally {
      this.loadingNodeId = '';
    }
  }

  private removeExpanded(noteId: string): void {
    const next: string[] = [];
    for (let index: number = 0; index < this.expandedIds.length; index++) {
      if (this.expandedIds[index] !== noteId) {
        next.push(this.expandedIds[index]);
      }
    }
    this.expandedIds = next;
  }

  private handleMockTap(node: DrawerTreeNode): void {
    for (let index: number = 0; index < this.mockItems.length; index++) {
      if (this.mockItems[index].id === node.noteId) {
        if (this.mockItems[index].type === DrawerItemType.FOLDER && this.mockItems[index].hasChildren) {
          this.mockItems[index].expanded = !this.mockItems[index].expanded;
          this.buildMockTree();
        } else if (this.mockItems[index].type === DrawerItemType.NOTE) {
          for (let itemIndex: number = 0; itemIndex < this.mockItems.length; itemIndex++) {
            this.mockItems[itemIndex].selected = this.mockItems[itemIndex].id === node.noteId;
          }
          this.selectedNoteId = node.noteId;
          AppStorage.setOrCreate(StateKeys.SELECTED_NOTE_TITLE, node.title);
          this.buildMockTree();
          this.onOpenNote(node.noteId, node.title);
          this.onCloseDrawer();
        }
        return;
      }
    }
  }

  private buildMockTree(): void {
    const query: string = this.searchText.trim().toLowerCase();
    const rows: DrawerTreeNode[] = [];
    const collapsedLevels: number[] = [];
    for (let index: number = 0; index < this.mockItems.length; index++) {
      const item: DrawerItem = this.mockItems[index];
      if (query.length > 0) {
        if (!item.label.toLowerCase().includes(query)) {
          continue;
        }
      } else {
        while (collapsedLevels.length > 0 && item.level <= collapsedLevels[collapsedLevels.length - 1]) {
          collapsedLevels.pop();
        }
        if (collapsedLevels.length > 0) {
          continue;
        }
      }
      rows.push(new DrawerTreeNode(item.id, item.label, item.level,
        item.type === DrawerItemType.FOLDER && item.hasChildren, item.expanded, item.selected,
        item.type === DrawerItemType.FOLDER ? 'book' : 'text', false));
      if (query.length === 0 && item.type === DrawerItemType.FOLDER && !item.expanded && item.hasChildren) {
        collapsedLevels.push(item.level);
      }
    }
    this.tree = rows;
    this.loadedNoteCount = rows.length;
  }

  private itemKey(item: DrawerTreeNode): string {
    return `${item.noteId}-${item.expanded}-${item.selected}-${item.level}`;
  }

  private formatClock(date: Date): string {
    const hours: string = date.getHours().toString().padStart(2, '0');
    const minutes: string = date.getMinutes().toString().padStart(2, '0');
    return `${hours}:${minutes}`;
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => resolve(), ms);
    });
  }

  private noteAttribute(noteId: string, name: string): string {
    const note: TriliumNote | undefined = this.noteCache.get(noteId);
    if (note === undefined) {
      return '';
    }
    for (let index: number = 0; index < note.attributes.length; index++) {
      const attribute = note.attributes[index];
      if (attribute.type === 'label' && attribute.name === name) {
        return attribute.value ?? '';
      }
    }
    return '';
  }

  private isMarkdownPreview(noteId: string): boolean {
    const note: TriliumNote | undefined = this.noteCache.get(noteId);
    if (note === undefined || note.type !== 'code') {
      return false;
    }
    const displayMode: string = this.noteAttribute(noteId, 'displayMode').toLowerCase();
    const language: string = this.noteAttribute(noteId, 'language').toLowerCase();
    return displayMode === 'preview' || language.indexOf('markdown') >= 0 ||
      note.mime.toLowerCase().indexOf('markdown') >= 0;
  }

  private isPdfAttachment(noteId: string): boolean {
    const note: TriliumNote | undefined = this.noteCache.get(noteId);
    return note !== undefined && note.type === 'file' &&
      note.mime.toLowerCase() === 'application/pdf';
  }

  private officialIconClass(noteId: string): string {
    const note: TriliumNote | undefined = this.noteCache.get(noteId);
    if (note === undefined) {
      return '';
    }
    const type: string = note.type;
    if (noteId === 'root') {
      return 'bx bx-home-alt-2';
    }
    if (noteId === '_share') {
      return 'bx bx-share-alt';
    }
    if (type === 'text') {
      if (this.noteAttribute(noteId, 'geolocation').length > 0 ||
        this.noteAttribute(noteId, 'mapPosition').length > 0) {
        return 'bx bx-pin';
      }
      const shape: string = this.noteAttribute(noteId, 'geoShape').length > 0 ?
        this.noteAttribute(noteId, 'geoShape') : this.noteAttribute(noteId, 'mapShape');
      if (shape.length > 0) {
        const kind: string = shape.split(':')[0];
        if (kind === 'polygon') return 'bx bx-shape-polygon';
        if (kind === 'circle') return 'bx bx-shape-circle';
        return 'bx bx-vector';
      }
      const clipType: string = this.noteAttribute(noteId, 'clipType');
      if (clipType === 'clippings') return 'bx bx-paperclip';
      if (clipType === 'page') return 'bx bx-globe';
      if (clipType === 'note') return 'bx bx-bookmark';
      if (clipType === 'tabs') return 'bx bx-window-alt';
      if (clipType === 'share') return 'bx bx-share';
      if (this.noteAttribute(noteId, 'meetingRecording').length > 0) {
        return 'bx bx-conversation';
      }
      const customDate: string = this.noteAttribute(noteId, 'calendar:startDate');
      if ((customDate.length > 0 && this.noteAttribute(noteId, customDate).length > 0) ||
        this.noteAttribute(noteId, 'startDate').length > 0) {
        return 'bx bx-calendar-event';
      }
      return note.hasVisibleChildren() ? 'bx bx-folder' : 'bx bx-note';
    }
    if (type === 'code') {
      return MIME_ICONS[note.mime] ?? 'bx bx-code';
    }
    if (type === 'file') {
      const mime: string = note.mime.toLowerCase();
      if (mime.startsWith('video/')) return 'bx bx-video';
      if (mime.startsWith('audio/')) return 'bx bx-music';
      if (mime === 'font/otf' || mime === 'font/sfnt' || mime === 'font/ttf' ||
        mime === 'font/woff' || mime === 'font/woff2' ||
        mime === 'application/font-woff' || mime === 'application/font-woff2' ||
        mime === 'application/x-font-opentype' || mime === 'application/x-font-otf' ||
        mime === 'application/x-font-truetype' || mime === 'application/x-font-ttf') {
        return 'bx bx-font';
      }
      if (mime === 'application/pdf') return 'bx bxs-file-pdf';
      if (mime === 'application/vnd.oasis.opendocument.text' ||
        mime === 'application/vnd.openxmlformats-officedocument.wordprocessingml.document') {
        return 'bx bxs-file-doc';
      }
      if (mime === 'application/gpx+xml') return 'bx bx-trip';
      if (mime === 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' ||
        mime === 'application/vnd.oasis.opendocument.spreadsheet' ||
        mime === 'application/vnd.ms-excel' || mime === 'text/csv') {
        return 'bx bx-spreadsheet';
      }
      if (mime === 'application/vnd.excalidraw+json') return 'bx bx-pen';
      if (mime === 'text/vnd.mermaid') return 'bx bx-selection';
      return 'bx bx-file';
    }
    if (type === 'image') {
      return note.mime.toLowerCase() === 'image/gif' ? 'bx bxs-file-gif' : 'bx bx-image';
    }
    const typeIcons: Record<string, string> = {
      'book': 'bx bx-book',
      'render': 'bx bx-extension',
      'search': 'bx bx-file-find',
      'relationMap': 'bx bx-shape-polygon',
      'noteMap': 'bx bxs-network-chart',
      'mermaid': 'bx bx-selection',
      'canvas': 'bx bx-pen',
      'webView': 'bx bx-globe-alt',
      'launcher': 'bx bx-link',
      'doc': 'bx bxs-file-doc',
      'contentWidget': 'bx bxs-widget',
      'mindMap': 'bx bx-sitemap',
      'spreadsheet': 'bx bx-table',
      'llmChat': 'bx bx-message-square-dots'
    };
    return typeIcons[type] ?? 'bx bx-file';
  }

  private rowIcon(item: DrawerTreeNode): Resource {
    const iconClass: string = this.noteAttribute(item.noteId, 'iconClass');
    if (iconClass.length > 0) {
      return AttributeVisuals.icon(iconClass);
    }
    if (item.type === 'book') {
      return $r('app.media.ic_book');
    }
    if (item.type === 'code') {
      return this.isMarkdownPreview(item.noteId) ? $r('app.media.ic_doc') :
        $r('app.media.ic_code');
    }
    if (item.type === 'search') {
      return $r('app.media.ic_search');
    }
    if (item.type === 'relationMap' || item.type === 'mindMap' || item.type === 'spreadsheet') {
      return $r('app.media.ic_layout');
    }
    if (item.type === 'text' && item.hasChildren) {
      return $r('app.media.ic_folder');
    }
    return $r('app.media.ic_doc');
  }

  private rowColor(item: DrawerTreeNode): string {
    return AttributeVisuals.color(this.noteAttribute(item.noteId, 'color'));
  }

  private rowGlyph(item: DrawerTreeNode): string {
    const iconClass: string = this.noteAttribute(item.noteId, 'iconClass');
    if (iconClass.length > 0) {
      return AttributeVisuals.glyph(iconClass);
    }
    return AttributeVisuals.glyph(this.officialIconClass(item.noteId));
  }

  @Builder
  private DrawerRow(item: DrawerTreeNode) {
    Row({ space: 7 }) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.loadingNodeId === item.noteId) {
          LoadingProgress()
            .width(13)
            .height(13)
            .color($r('app.color.primary_text'))
        } else if (item.hasChildren) {
          AppIcon({
            icon: item.expanded ? $r('app.media.ic_chevron_down') : $r('app.media.ic_chevron_right'),
            iconSize: 12,
            tint: item.selected ? $r('app.color.text_on_primary') : $r('app.color.text_tertiary')
          })
        }
      }
      .width(14)
      .height(24)
      .onClick(() => {
        this.toggleNode(item);
      })

      if (this.rowGlyph(item).length > 0) {
        Text(this.rowGlyph(item))
          .fontFamily(AttributeVisuals.FONT_FAMILY)
          .fontSize(18)
          .fontColor(item.selected ? $r('app.color.text_on_primary') :
            (this.noteAttribute(item.noteId, 'color').length > 0
              ? this.rowColor(item) : $r('app.color.text_secondary')))
      } else {
        AppIcon({
          icon: this.rowIcon(item),
          iconSize: 15,
          tint: item.selected ? $r('app.color.text_on_primary') : $r('app.color.text_secondary')
        })
      }

      Text(item.title)
        .layoutWeight(1)
        .fontSize(item.level <= 1 ? 14 : 13.5)
        .fontWeight(item.selected ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(item.selected ? $r('app.color.text_on_primary') :
          (this.noteAttribute(item.noteId, 'color').length > 0
            ? this.rowColor(item) : $r('app.color.text_primary')))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (item.isProtected) {
        AppIcon({
          icon: $r('app.media.ic_lock'),
          iconSize: 12,
          tint: item.selected ? $r('app.color.text_on_primary') : $r('app.color.text_tertiary')
        })
      }
    }
    .width('100%')
    .height(35)
    .padding({ left: 7 + item.level * 15, right: 11 })
    .backgroundColor(item.selected ? $r('app.color.primary') : Color.Transparent)
    .borderRadius(8)
    .margin({ bottom: 2 })
    .onClick(() => {
      this.handleNodeTap(item);
    })
  }

  @Builder
  private SyncFooter() {
    Row({ space: 6 }) {
      AppIcon({
        icon: $r('app.media.ic_cloud'),
        iconSize: 15,
        tint: this.hasSyncError ? $r('app.color.danger') : $r('app.color.text_tertiary')
      })
      Text(this.syncMessage)
        .fontSize(12)
        .fontColor(this.hasSyncError ? $r('app.color.danger') : $r('app.color.text_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Row()
        .width(6)
        .height(6)
        .borderRadius(3)
        .backgroundColor(this.hasSyncError ? $r('app.color.danger') : $r('app.color.success'))
    }
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        LogoMark({ markSize: 24, showGlow: false })
        Text(AppConstants.APP_NAME)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .letterSpacing(0.2)
        Blank()
        Text(AppConstants.APP_VERSION)
          .fontSize(9.5)
          .fontColor($r('app.color.text_tertiary'))
          .opacity(0.45)
      }
      .width('100%')
      .height(58)
      .padding({ left: 16, right: 14 })

      if (this.isNetworkOffline) {
        Row({ space: 9 }) {
          AppIcon({
            icon: $r('app.media.ic_sync'),
            iconSize: 16,
            tint: $r('app.color.warning')
          })
          Column({ space: 2 }) {
            Text('网络不可用')
              .fontSize(12.5)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.warning'))
              .width('100%')
            Text(this.cachedNotes.length > 0
              ? '当前显示最近缓存的笔记，联网后下拉刷新'
              : '请检查网络后下拉重试')
              .fontSize(10.5)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(2)
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('calc(100% - 28vp)')
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .margin({ bottom: 8 })
        .backgroundColor($r('app.color.bg_secondary'))
        .border({ width: { left: 3 }, color: $r('app.color.warning') })
        .borderRadius(9)
        .alignSelf(ItemAlign.Center)
      }

      Row({ space: 8 }) {
        AppIcon({
          icon: $r('app.media.ic_search'),
          iconSize: 16,
          tint: $r('app.color.text_tertiary')
        })
        Text('搜索全部笔记…')
          .layoutWeight(1)
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('calc(100% - 28vp)')
      .height(40)
      .padding({ left: 13, right: 13 })
      .backgroundColor($r('app.color.bg_input'))
      .borderRadius(20)
      .border({ width: 1, color: $r('app.color.border') })
      .margin({ top: 4 })
      .alignSelf(ItemAlign.Center)
      .onClick(() => {
        this.onOpenGlobalSearch();
        this.onCloseDrawer();
      })

      Row() {
        Text('笔记树')
          .fontSize(10.5)
          .fontColor($r('app.color.text_tertiary'))
          .letterSpacing(0.3)
        Blank()
        Text(`${this.loadedNoteCount} 项`)
          .fontSize(10.5)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .padding({ left: 17, right: 17, top: 13, bottom: 2 })

      Refresh({ refreshing: $$this.isRefreshing }) {
        Scroll() {
          Column() {
            if (this.tree.length === 0) {
              Column({ space: 10 }) {
                if (this.isSyncing) {
                  LoadingProgress()
                    .width(24)
                    .height(24)
                    .color($r('app.color.primary'))
                  Text('正在同步笔记树…')
                    .fontSize(12.5)
                    .fontColor($r('app.color.text_tertiary'))
                } else if (this.hasSyncError) {
                  Text(this.syncMessage)
                    .fontSize(12.5)
                    .fontColor($r('app.color.danger'))
                    .textAlign(TextAlign.Center)
                  Button('重试')
                    .type(ButtonType.Capsule)
                    .height(34)
                    .fontSize(13)
                    .backgroundColor($r('app.color.primary_soft'))
                    .fontColor($r('app.color.primary_text'))
                    .onClick(() => {
                      this.syncTree(false);
                    })
                } else {
                  Text(this.searchText.length > 0 ? '没有匹配的笔记' : '暂无笔记')
                    .fontSize(12.5)
                    .fontColor($r('app.color.text_tertiary'))
                }
              }
              .width('100%')
              .height(180)
              .justifyContent(FlexAlign.Center)
            } else {
              Column({ space: 0 }) {
                ForEach(this.tree, (item: DrawerTreeNode) => {
                  this.DrawerRow(item)
                }, (item: DrawerTreeNode) => this.itemKey(item))
              }
              .width('100%')
              .padding({ left: 10, right: 10, top: 8, bottom: 14 })
            }

            if (this.hasSyncError && this.cachedNotes.length > 0) {
              Column({ space: 0 }) {
                Row() {
                  Text('离线缓存')
                    .fontSize(10.5)
                    .fontColor($r('app.color.warning'))
                    .letterSpacing(0.3)
                  Blank()
                  Text('最近阅读')
                    .fontSize(10.5)
                    .fontColor($r('app.color.text_tertiary'))
                }
                .width('100%')
                .padding({ left: 8, right: 8, top: 10, bottom: 6 })

                ForEach(this.cachedNotes, (item: CachedNote) => {
                  Row({ space: 9 }) {
                    Stack({ alignContent: Alignment.Center }) {
                      AppIcon({
                        icon: $r('app.media.ic_clock'),
                        iconSize: 15,
                        tint: $r('app.color.warning')
                      })
                    }
                    .width(30)
                    .height(30)
                    .borderRadius(8)
                    .backgroundColor($r('app.color.bg_secondary'))

                    Column({ space: 2 }) {
                      Text(item.title.length > 0 ? item.title : '未命名笔记')
                        .fontSize(13.5)
                        .fontColor($r('app.color.text_primary'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                      Text(`${this.formatCachedTime(item.cachedAt)} 缓存`)
                        .fontSize(10.5)
                        .fontColor($r('app.color.text_tertiary'))
                        .width('100%')
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                  }
                  .width('100%')
                  .height(50)
                  .padding({ left: 8, right: 8 })
                  .borderRadius(8)
                  .onClick(() => {
                    this.openCachedNote(item);
                  })
                }, (item: CachedNote) => item.noteId)
              }
              .width('100%')
              .padding({ left: 10, right: 10, bottom: 14 })
            }
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.Top)
      }
      .layoutWeight(1)
      .width('100%')
      .onRefreshing(() => {
        this.syncTree(true);
      })

      Column() {
        Button({ type: ButtonType.Capsule, stateEffect: true }) {
          Row({ space: 7 }) {
            AppIcon({
              icon: $r('app.media.ic_plus'),
              iconSize: 16,
              tint: $r('app.color.text_on_primary')
            })
            Text('新建笔记')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_on_primary'))
          }
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .height(44)
        .borderRadius(22)
        .backgroundColor($r('app.color.primary'))
        .onClick(this.onNewNote)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 6, bottom: 8 })

      Row() {
        Row({ space: 6 }) {
          AppIcon({
            icon: $r('app.media.ic_settings'),
            iconSize: 16,
            tint: $r('app.color.text_secondary')
          })
          Text('设置')
            .fontSize(12.5)
            .fontColor($r('app.color.text_secondary'))
        }
        .onClick(this.onOpenSettings)

        Row({ space: 5 }) {
          Text(AttributeVisuals.glyph('bx bxs-network-chart'))
            .fontFamily(AttributeVisuals.FONT_FAMILY)
            .fontSize(16)
            .fontColor($r('app.color.text_secondary'))
          Text('地图')
            .fontSize(12.5)
            .fontColor($r('app.color.text_secondary'))
        }
        .margin({ left: 14 })
        .onClick(this.onOpenNoteMap)

        Blank()
        this.SyncFooter()
      }
      .width('100%')
      .height(48)
      .padding({ left: 17, right: 17 })
      .border({ width: { top: 1 }, color: $r('app.color.divider') })
      .backgroundColor($r('app.color.bg_secondary'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_secondary'))
    .onClick(() => {
      const tick: number = AppStorage.get<number>('TEXT_SELECTION_DISMISS') ?? 0;
      AppStorage.setOrCreate('TEXT_SELECTION_DISMISS', tick + 1);
    })
  }
}
