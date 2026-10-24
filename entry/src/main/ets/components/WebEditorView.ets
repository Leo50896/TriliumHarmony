import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { StateKeys } from '../constants/StateKeys';
import { ImageDiskCache } from '../services/ImageDiskCache';

class EditorBridge {
  onHtml: (html: string) => void = () => {};
  onLink: (noteId: string) => void = () => {};
  onReady: () => void = () => {};
  onError: (message: string) => void = () => {};

  postHtml(html: string): void {
    this.onHtml(html);
  }

  postLink(noteId: string): void {
    this.onLink(noteId);
  }

  postReady(value: string): void {
    if (value.length > 0) {
      this.onReady();
    }
  }

  postError(message: string): void {
    this.onError(message);
  }
}

/**
 * WebView host for the CKEditor-based reading/editing surface.
 *
 * The native side only owns lifecycle and LocalStore persistence; all document
 * rendering and editing is done by rawfile/editor.html.
 */
@Component
export struct WebEditorView {
  @Prop @Watch('onContentChanged') content: string = '';
  @Prop @Watch('onReadOnlyChanged') readOnly: boolean = true;
  @Prop @Watch('onSaveTick') saveTick: number = 0;
  @Prop noteId: string = '';
  onHtml: (html: string) => void = () => {};
  onLink: (noteId: string) => void = () => {};
  onError: (message: string) => void = () => {};
  @StorageLink(StateKeys.THEME_MODE) private themeMode: string = 'light';
  @State private pageReady: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: EditorBridge = new EditorBridge();

  aboutToAppear(): void {
    this.bridge.onHtml = (html: string) => {
      this.onHtml(html);
    };
    this.bridge.onLink = (noteId: string) => {
      this.onLink(noteId);
    };
    this.bridge.onReady = () => {
      this.pageReady = true;
      this.injectAll();
    };
    this.bridge.onError = (message: string) => {
      this.onError(message);
    };
  }

  private scriptString(value: string): string {
    return JSON.stringify(value).replace(/</g, '\\u003c');
  }

  private injectAll(): void {
    if (!this.pageReady) {
      return;
    }
    const html: string = this.scriptString(this.content);
    const theme: string = this.themeMode === 'dark' ? 'dark' : 'light';
    const script: string = `window.NativeEditor.init(${html}, ${this.readOnly}, "${theme}")`;
    this.controller.runJavaScript(script);
  }

  private onContentChanged(): void {
    if (!this.pageReady) {
      return;
    }
    this.controller.runJavaScript(`window.NativeEditor.setHtml(${this.scriptString(this.content)})`);
  }

  private onReadOnlyChanged(): void {
    if (!this.pageReady) {
      return;
    }
    this.controller.runJavaScript(`window.NativeEditor.setReadOnly(${this.readOnly})`);
    if (!this.readOnly) {
      this.controller.runJavaScript('window.NativeEditor.focus()');
    }
  }

  private onSaveTick(): void {
    if (!this.pageReady || this.saveTick === 0) {
      return;
    }
    this.controller.runJavaScript('window.NativeEditor.flush()');
  }

  private interceptImage(url: string): WebResourceResponse | null {
    if (url.indexOf('/etapi/attachments/') < 0 && url.indexOf('/etapi/images/') < 0 &&
      url.indexOf('/api/attachments/') < 0 && url.indexOf('/etapi/notes/') < 0) {
      return null;
    }
    const context: common.UIAbilityContext | null =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context === null) {
      return null;
    }
    const serverUrl = AppStorage.get<string>('auth.serverUrl');
    const key: string = ImageDiskCache.keyForSync(serverUrl ?? '', url);
    const buffer: ArrayBuffer | null = ImageDiskCache.readBufferSync(context, key);
    if (buffer === null) {
      return null;
    }
    let mime: string = 'image/jpeg';
    const lower: string = url.toLowerCase();
    if (lower.indexOf('.png') >= 0) {
      mime = 'image/png';
    } else if (lower.indexOf('.gif') >= 0) {
      mime = 'image/gif';
    } else if (lower.indexOf('.webp') >= 0) {
      mime = 'image/webp';
    }
    const response: WebResourceResponse = new WebResourceResponse();
    response.setResponseData(buffer);
    response.setResponseMimeType(mime);
    response.setResponseEncoding('binary');
    response.setResponseCode(200);
    return response;
  }

  build() {
    Web({ src: $rawfile('editor.html'), controller: this.controller })
      .width('100%')
      .height(720)
      .backgroundColor('#1e1f22')
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .fileAccess(true)
      .imageAccess(true)
      .horizontalScrollBarAccess(false)
      .verticalScrollBarAccess(false)
      .javaScriptProxy({
        object: this.bridge,
        name: 'NativeEditorBridge',
        methodList: ['postHtml', 'postLink', 'postReady', 'postError'],
        controller: this.controller
      })
      .onPageEnd(() => {
        this.pageReady = true;
        this.injectAll();
      })
      .onInterceptRequest((event) => {
        return this.interceptImage(event.request.getRequestUrl());
      })
      .onErrorReceive((event) => {
        if (event && event.error) {
          this.onError(event.error.getErrorInfo());
        }
      })
  }
}
