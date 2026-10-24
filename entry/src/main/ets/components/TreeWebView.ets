import { webview } from '@kit.ArkWeb';
import { StateKeys } from '../constants/StateKeys';

class TreeBridge {
  onSelect: (noteId: string, title: string) => void = () => {};
  onToggle: (noteId: string) => void = () => {};

  selectNote(noteId: string, title: string): void {
    this.onSelect(noteId, title);
  }

  toggleNote(noteId: string): void {
    this.onToggle(noteId);
  }
}

@Component
export struct TreeWebView {
  @Prop @Watch('onTreeChanged') treeJson: string = '[]';
  onSelect: (noteId: string, title: string) => void = () => {};
  onToggle: (noteId: string) => void = () => {};
  @StorageLink(StateKeys.THEME_MODE) private themeMode: string = 'light';
  @State private ready: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: TreeBridge = new TreeBridge();

  aboutToAppear(): void {
    this.bridge.onSelect = (noteId: string, title: string) => {
      this.onSelect(noteId, title);
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
    this.controller.runJavaScript(`window.NativeTree.setTheme("${theme}")`);
    this.controller.runJavaScript(`window.NativeTree.render(${this.jstr(this.treeJson)})`);
    this.controller.runJavaScript('window.NativeTree.scrollToSelected()');
  }

  private onTreeChanged(): void {
    this.inject();
  }

  build() {
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
        methodList: ['selectNote', 'toggleNote'],
        controller: this.controller
      })
      .onPageEnd(() => {
        this.ready = true;
        this.inject();
      })
  }
}
