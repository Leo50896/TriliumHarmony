import { webview } from '@kit.ArkWeb';
import { StateKeys } from '../constants/StateKeys';

class TreeBridge {
  onSelect: (noteId: string) => void = () => {};
  onToggle: (noteId: string) => void = () => {};

  onNoteSelected(noteId: string): void {
    this.onSelect(noteId);
  }

  toggleNote(noteId: string): void {
    this.onToggle(noteId);
  }
}

@Component
export struct TreeWebView {
  @Prop @Watch('onTreeChanged') treeJson: string = '[]';
  @Prop @Watch('onActiveChanged') activeNoteId: string = '';
  onSelect: (noteId: string) => void = () => {};
  onToggle: (noteId: string) => void = () => {};
  @StorageLink(StateKeys.THEME_MODE) private themeMode: string = 'light';
  @State private ready: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: TreeBridge = new TreeBridge();

  aboutToAppear(): void {
    this.bridge.onSelect = (noteId: string) => {
      this.onSelect(noteId);
    };
    this.bridge.onToggle = (noteId: string) => {
      this.onToggle(noteId);
    };
  }

  private jstr(value: string): string {
    return JSON.stringify(value).replace(/</g, '\\u003c');
  }

  private inject(): void {
    if (!this.ready) {
      return;
    }
    const theme: string = this.themeMode === 'dark' ? 'dark' : 'light';
    this.controller.runJavaScript(`window.setTheme("${theme}")`);
    this.controller.runJavaScript(`window.renderTree(${this.jstr(this.treeJson)})`);
    this.controller.runJavaScript(`window.setActiveNote(${this.jstr(this.activeNoteId)})`);
  }

  private onTreeChanged(): void {
    this.inject();
  }

  private onActiveChanged(): void {
    if (!this.ready) {
      return;
    }
    this.controller.runJavaScript(`window.setActiveNote(${this.jstr(this.activeNoteId)})`);
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (!this.ready) {
        Column({ space: 10 }) {
          ForEach([0, 1, 2, 3, 4, 5], (index: number) => {
            Row({ space: 8 }) {
              Column()
                .width(20)
                .height(20)
                .borderRadius(5)
                .backgroundColor('#2a2d32')
              Column()
                .width(`${72 - (index % 3) * 12}%`)
                .height(13)
                .borderRadius(4)
                .backgroundColor('#2a2d32')
              Blank()
            }
            .width('100%')
            .height(38)
            .padding({ left: 12 + (index % 3) * 12, right: 12 })
          }, (index: number) => `skeleton-${index}`)
        }
        .width('100%')
        .padding({ top: 12 })
        .backgroundColor('#1e1f22')
      }

      Web({ src: $rawfile('tree.html'), controller: this.controller })
        .width('100%')
        .height('100%')
        .backgroundColor('#1e1f22')
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .horizontalScrollBarAccess(false)
        .verticalScrollBarAccess(true)
        .javaScriptProxy({
          object: this.bridge,
          name: 'NativeTreeBridge',
          methodList: ['onNoteSelected', 'toggleNote'],
          controller: this.controller
        })
        .onPageEnd(() => {
          this.ready = true;
          this.inject();
        })
    }
    .width('100%')
    .height('100%')
  }
}
