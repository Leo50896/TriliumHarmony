import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { AppIcon } from '../components/AppIcon';
import { AuthSession } from '../models/AuthModels';
import { CachedNote } from '../models/CacheModels';
import { TriliumNote } from '../models/TriliumModels';
import { LocalStore } from '../services/LocalStore';
import { SessionStore } from '../services/SessionStore';
import { AttributeVisuals } from '../utils/AttributeVisuals';
import { StateKeys } from '../constants/StateKeys';

class WebMapNode {
  id: string;
  title: string;
  type: string;
  color: string;
  folder: boolean;
  depth: number;

  constructor(id: string, title: string, type: string, color: string, folder: boolean, depth: number) {
    this.id = id;
    this.title = title;
    this.type = type;
    this.color = color;
    this.folder = folder;
    this.depth = depth;
  }
}

class WebMapLink {
  source: string;
  target: string;
  kind: string;
  label: string;

  constructor(source: string, target: string, kind: string, label: string = '') {
    this.source = source;
    this.target = target;
    this.kind = kind;
    this.label = label;
  }
}

class WebMapPayload {
  nodes: WebMapNode[] = [];
  links: WebMapLink[] = [];
  dark: boolean = true;
  mode: string = 'tree';
}

class WebNoteInfo {
  noteId: string;
  title: string;
  path: string;
  type: string;
  labels: string[];

  constructor(noteId: string, title: string, path: string, type: string, labels: string[]) {
    this.noteId = noteId;
    this.title = title;
    this.path = path;
    this.type = type;
    this.labels = labels;
  }
}

class MapBridge {
  private tap: (noteId: string) => void;
  private ready: () => void;
  private blank: () => void;
  private open: (noteId: string) => void;
  private zoom: (value: number) => void;

  constructor(tap: (noteId: string) => void, ready: () => void, blank: () => void,
    open: (noteId: string) => void, zoom: (value: number) => void) {
    this.tap = tap;
    this.ready = ready;
    this.blank = blank;
    this.open = open;
    this.zoom = zoom;
  }

  onNoteTap(noteId: string): void {
    this.tap(noteId);
  }

  onOpenTap(noteId: string): void {
    this.open(noteId);
  }

  onBlankTap(): void {
    this.blank();
  }

  onReady(): void {
    this.ready();
  }

  onZoomChanged(value: number): void {
    this.zoom(value);
  }
}

/**
 * Note map rendered by D3 inside a WebView. The native side only supplies the
 * nodes/links JSON and receives node taps; layout, zoom, pan and labels are D3's.
 */
@Component
export struct NoteMapView {
  onBack: () => void = () => {};
  onOpenNote: (noteId: string) => void = () => {};

  @StorageProp(StateKeys.SELECTED_NOTE_ID) private selectedNoteId: string = '';
  @State private layoutMode: string = 'tree';
  @State private loading: boolean = true;
  @State private message: string = '';
  @State private nodeCount: number = 0;
  @State private zoomLevel: number = 100;
  @State private sheet: WebNoteInfo | null = null;

  private controller: webview.WebviewController = new webview.WebviewController();
  private pageReady: boolean = false;
  private dataReady: boolean = false;
  private payload: WebMapPayload = new WebMapPayload();
  private notesById: Map<string, TriliumNote> = new Map();
  private bridge: MapBridge = new MapBridge((noteId: string) => {
    this.selectNote(noteId);
  }, () => {
    this.pageReady = true;
    this.pushData();
  }, () => {
    this.closeSheet();
  }, (noteId: string) => {
    this.onOpenNote(noteId);
  }, (value: number) => {
    const percent: number = Math.round(value * 100);
    if (Math.abs(percent - this.zoomLevel) > 1) {
      this.zoomLevel = percent;
    }
  });

  aboutToAppear(): void {
    this.loadNotes();
  }

  private context(): common.UIAbilityContext | null {
    const hostContext: common.Context | undefined = this.getUIContext().getHostContext();
    return hostContext === undefined ? null : hostContext as common.UIAbilityContext;
  }

  private attributeValue(note: TriliumNote, name: string): string {
    for (let i = 0; i < note.attributes.length; i++) {
      const attribute = note.attributes[i];
      if (attribute.type === 'label' && attribute.name === name) {
        return attribute.value ?? '';
      }
    }
    return '';
  }

  private relationLabel(note: TriliumNote, targetId: string): string {
    for (let i = 0; i < note.attributes.length; i++) {
      const attribute = note.attributes[i];
      if (attribute.type === 'relation' && attribute.value === targetId) {
        return attribute.name ?? '';
      }
    }
    return '';
  }

  private bodyLinks(content: string): string[] {
    const ids: string[] = [];
    const bodyPattern = /\[\[([A-Za-z0-9_-]{8,})\]\]/g;
    let match: RegExpExecArray | null = bodyPattern.exec(content);
    while (match !== null) {
      ids.push(match[1]);
      match = bodyPattern.exec(content);
    }
    const hrefPattern = /href="#root\/(?:[A-Za-z0-9_-]+\/)*([A-Za-z0-9_-]+)"/g;
    match = hrefPattern.exec(content);
    while (match !== null) {
      ids.push(match[1]);
      match = hrefPattern.exec(content);
    }
    return ids;
  }

  private async loadNotes(): Promise<void> {
    const context: common.UIAbilityContext | null = this.context();
    const session: AuthSession | null = SessionStore.currentSession();
    if (context === null || session === null) {
      this.loading = false;
      this.message = '当前未登录';
      return;
    }
    try {
      const notes: TriliumNote[] = await LocalStore.all(context, SessionStore.accountKey());
      const cached: CachedNote[] = await LocalStore.recent(context, SessionStore.accountKey(), 600);
      const contents: Map<string, string> = new Map();
      for (let i = 0; i < cached.length; i++) {
        contents.set(cached[i].noteId, cached[i].content);
      }
      this.buildPayload(notes.filter((note: TriliumNote) =>
        note.noteId === 'root' || !note.noteId.startsWith('_')), contents);
      this.loading = false;
      this.dataReady = true;
      this.nodeCount = this.payload.nodes.length;
      this.pushData();
    } catch (error) {
      this.loading = false;
      this.message = '笔记地图加载失败';
    }
  }

  private notePath(noteId: string, guard: number = 0): string {
    const note: TriliumNote | undefined = this.notesById.get(noteId);
    if (note === undefined) return '';
    if (noteId === 'root' || note.parentNoteIds.length === 0 || guard > 8) return note.title;
    const parent: string = this.notePath(note.parentNoteIds[0], guard + 1);
    return parent.length > 0 ? `${parent} / ${note.title}` : note.title;
  }

  private typeLabel(type: string): string {
    const labels: Record<string, string> = {
      'text': '文本', 'code': '代码', 'book': '书籍', 'file': '文件',
      'image': '图片', 'canvas': '画布', 'mermaid': '图表', 'spreadsheet': '表格',
      'relationMap': '关系图', 'noteMap': '笔记地图', 'mindMap': '思维导图',
      'webView': '网页', 'search': '搜索', 'doc': '文档'
    };
    return labels[type] ?? type;
  }

  private noteLabels(note: TriliumNote): string[] {
    const labels: string[] = [];
    for (let i = 0; i < note.attributes.length; i++) {
      const attribute = note.attributes[i];
      if (attribute.type !== 'label') continue;
      const value: string = attribute.value ?? '';
      labels.push(value.length > 0 ? `#${attribute.name}=${value}` : `#${attribute.name}`);
      if (labels.length >= 6) break;
    }
    return labels;
  }

  private selectNote(noteId: string): void {
    const note: TriliumNote | undefined = this.notesById.get(noteId);
    if (note === undefined) return;
    this.sheet = new WebNoteInfo(note.noteId, note.title, this.notePath(note.noteId),
      this.typeLabel(note.type), this.noteLabels(note));
  }

  private closeSheet(): void {
    this.sheet = null;
  }

  private buildPayload(notes: TriliumNote[], contents: Map<string, string>): void {
    const byId: Map<string, TriliumNote> = new Map();
    const nodes: WebMapNode[] = [];
    for (let i = 0; i < notes.length; i++) {
      byId.set(notes[i].noteId, notes[i]);
    }
    this.notesById = byId;
    const children: Map<string, string[]> = new Map();
    const depth: Map<string, number> = new Map();
    for (let i = 0; i < notes.length; i++) {
      const note: TriliumNote = notes[i];
      for (let p = 0; p < note.parentNoteIds.length; p++) {
        const parentId: string = note.parentNoteIds[p];
        if (!byId.has(parentId)) continue;
        const list: string[] | undefined = children.get(parentId);
        if (list === undefined) children.set(parentId, [note.noteId]);
        else list.push(note.noteId);
      }
    }
    let frontier: string[] = this.findNode(notes, 'root') === undefined ? [] : ['root'];
    const seen: Set<string> = new Set(frontier);
    let level: number = 0;
    while (frontier.length > 0) {
      const next: string[] = [];
      for (let i = 0; i < frontier.length; i++) {
        depth.set(frontier[i], level);
        const kids: string[] = children.get(frontier[i]) ?? [];
        for (let k = 0; k < kids.length; k++) {
          if (!seen.has(kids[k])) {
            seen.add(kids[k]);
            next.push(kids[k]);
          }
        }
      }
      frontier = next;
      level++;
    }
    for (let i = 0; i < notes.length; i++) {
      const note: TriliumNote = notes[i];
      const colorValue: string = this.attributeValue(note, 'color');
      nodes.push(new WebMapNode(note.noteId, note.title, note.type,
        colorValue.length > 0 ? AttributeVisuals.color(colorValue) : '',
        note.noteId === 'root' || note.hasVisibleChildren(), depth.get(note.noteId) ?? 99));
    }

    const links: WebMapLink[] = [];
    for (let i = 0; i < notes.length; i++) {
      const note: TriliumNote = notes[i];
      for (let p = 0; p < note.parentNoteIds.length; p++) {
        if (byId.has(note.parentNoteIds[p])) {
          links.push(new WebMapLink(note.parentNoteIds[p], note.noteId, 'parent'));
        }
      }
      for (let a = 0; a < note.attributes.length; a++) {
        const attribute = note.attributes[a];
        if (attribute.type === 'relation' && (attribute.value ?? '').length > 0 &&
          byId.has(attribute.value ?? '')) {
          links.push(new WebMapLink(note.noteId, attribute.value ?? '', 'relation',
            this.relationLabel(note, attribute.value ?? '')));
        }
      }
      const content: string = contents.get(note.noteId) ?? '';
      const body: string[] = this.bodyLinks(content);
      for (let b = 0; b < body.length; b++) {
        if (byId.has(body[b]) && body[b] !== note.noteId) {
          links.push(new WebMapLink(note.noteId, body[b], 'body'));
        }
      }
    }

    const selectedNote: TriliumNote | undefined = byId.get(this.selectedNoteId);
    const rootNote: TriliumNote | undefined = byId.get('root');
    const source: TriliumNote | undefined = selectedNote ?? rootNote;
    const mapType: string = source !== undefined ? this.attributeValue(source, 'mapType') : '';
    this.layoutMode = mapType === 'link' ? 'link' : 'tree';

    this.payload = new WebMapPayload();
    this.payload.nodes = nodes;
    this.payload.links = links;
  }

  private findNode(notes: TriliumNote[], id: string): TriliumNote | undefined {
    for (let i = 0; i < notes.length; i++) {
      if (notes[i].noteId === id) return notes[i];
    }
    return undefined;
  }

  private pushData(): void {
    if (!this.pageReady || !this.dataReady) return;
    const rich: WebMapPayload = new WebMapPayload();
    if (this.layoutMode === 'tree') {
      rich.nodes = this.payload.nodes;
      rich.links = this.payload.links.filter((link: WebMapLink) => link.kind === 'parent');
    } else {
      // Mirrors a Trilium note-map note in link mode: all notes of the pulled
      // map are present, but the edges are relations/internal links only.
      // Parent edges belong to the tree map and must not be drawn here.
      const activeLinks: WebMapLink[] = [];
      const seen: Set<string> = new Set();
      for (let i = 0; i < this.payload.links.length; i++) {
        const link: WebMapLink = this.payload.links[i];
        if (link.kind === 'parent') {
          continue;
        }
        const key: string = `${link.source}|${link.target}`;
        if (seen.has(key)) continue;
        seen.add(key);
        activeLinks.push(link);
      }
      rich.links = activeLinks;
      rich.nodes = this.payload.nodes;
    }
    rich.dark = AppStorage.get<number>('colorMode') === 0;
    rich.mode = this.layoutMode;
    this.nodeCount = rich.nodes.length;
    const json: string = JSON.stringify(rich);
    const encoded: string = JSON.stringify(json);
    const focus: string = this.layoutMode === 'tree' ? 'focusMapRoot();' : 'fitMap(true);';
    this.controller.runJavaScript(`renderMapJson(${encoded}); ${focus}`);
  }

  private setMode(mode: string): void {
    if (this.layoutMode === mode) return;
    this.layoutMode = mode;
    this.pushData();
  }

  @Builder
  private ModeButton(mode: string, glyph: string, label: string) {
    Row({ space: 5 }) {
      Text(AttributeVisuals.glyph(glyph))
        .fontFamily(AttributeVisuals.FONT_FAMILY)
        .fontSize(15)
        .fontColor(this.layoutMode === mode ? $r('app.color.primary') : $r('app.color.text_secondary'))
      Text(label)
        .fontSize(11)
        .fontColor(this.layoutMode === mode ? $r('app.color.primary') : $r('app.color.text_secondary'))
    }
    .height(32)
    .padding({ left: 9, right: 9 })
    .borderRadius(8)
    .backgroundColor(this.layoutMode === mode ? $r('app.color.primary_soft') : $r('app.color.bg_secondary'))
    .onClick(() => {
      this.setMode(mode);
    })
  }

  @Builder
  private NoteSheet(info: WebNoteInfo) {
    Column({ space: 7 }) {
      Row() {
        Text(info.title)
          .fontSize(15.5)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text('✕')
          .fontSize(14)
          .fontColor($r('app.color.text_tertiary'))
          .padding(4)
          .onClick(() => {
            this.closeSheet();
          })
      }
      if (info.path.length > 0 && info.path !== info.title) {
        Text(info.path)
          .fontSize(10.5)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      Row({ space: 5 }) {
        Text(info.type)
          .fontSize(9.5)
          .fontColor($r('app.color.primary'))
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .borderRadius(9)
          .backgroundColor($r('app.color.primary_soft'))
        ForEach(info.labels.slice(0, 2), (label: string) => {
          Text(label)
            .fontSize(9.5)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .borderRadius(9)
            .backgroundColor($r('app.color.bg_secondary'))
        }, (label: string) => label)
      }
      Button('打开笔记')
        .width('100%')
        .height(36)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .backgroundColor($r('app.color.primary'))
        .fontColor($r('app.color.text_on_primary'))
        .borderRadius(10)
        .onClick(() => {
          this.closeSheet();
          this.onOpenNote(info.noteId);
        })
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.bg_elevated'))
    .borderRadius({ topLeft: 20, topRight: 20, bottomLeft: 12, bottomRight: 12 })
    .shadow({ radius: 18, color: $r('app.color.shadow'), offsetY: -4 })
    .margin({ left: 8, right: 8, bottom: 8 })
    .align(Alignment.Bottom)
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Stack({ alignContent: Alignment.Center }) {
          AppIcon({
            icon: $r('app.media.ic_back'),
            iconSize: 21,
            tint: $r('app.color.text_primary')
          })
        }
        .width(38)
        .height(38)
        .borderRadius(19)
        .onClick(this.onBack)
        Text('笔记地图')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(`${this.nodeCount} 个节点`)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 14 })

      Stack({ alignContent: Alignment.Center }) {
        Web({ src: $rawfile('map.html'), controller: this.controller })
          .width('100%')
          .height('100%')
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .javaScriptProxy({
            object: this.bridge,
            name: 'arkBridge',
            methodList: ['onNoteTap', 'onReady', 'onBlankTap', 'onOpenTap', 'onZoomChanged'],
            controller: this.controller
          })
          .onPageEnd(() => {
            this.pageReady = true;
            this.pushData();
          })

        Row({ space: 4 }) {
          this.ModeButton('link', 'bx bx-network-chart', '链接')
          this.ModeButton('tree', 'bx bx-sitemap', '树形')
        }
        .position({ x: 10, y: 10 })
        .zIndex(20)
        .padding(3)
        .borderRadius(12)
        .backgroundColor($r('app.color.bg_primary'))
        .opacity(0.92)

        Row({ space: 6 }) {
          Text('−')
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
          Slider({
            value: this.zoomLevel,
            min: 15,
            max: 300,
            step: 5,
            style: SliderStyle.OutSet
          })
            .width(110)
            .trackThickness(3)
            .selectedColor($r('app.color.primary'))
            .onChange((value: number, mode: SliderChangeMode) => {
              this.zoomLevel = value;
              this.controller.runJavaScript(`setMapZoom(${(value / 100).toFixed(2)});`);
            })
          Text('+')
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
        }
        .height(36)
        .padding({ left: 10, right: 10 })
        .borderRadius(18)
        .backgroundColor($r('app.color.bg_surface'))
        .opacity(0.94)
        .position({ x: 12, y: '86%' })
        .zIndex(20)

        if (this.loading) {
          Column({ space: 10 }) {
            LoadingProgress()
              .width(26)
              .height(26)
              .color($r('app.color.primary'))
            Text('正在构建笔记地图…')
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
          }
        } else if (this.message.length > 0) {
          Text(this.message)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }
}
