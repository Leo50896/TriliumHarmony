import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { StateKeys } from '../constants/StateKeys';
import { ImageDiskCache } from '../services/ImageDiskCache';
import { EtapiService } from '../services/EtapiService';
import { SessionStore } from '../services/SessionStore';

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
  private downloading: Set<string> = new Set();

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
      // Never let a cache miss fall through to an unauthenticated WebView
      // request. Return a transparent placeholder immediately and replace the
      // corresponding <img> asynchronously after the token download finishes.
      this.downloadAndReplace(url, context, key);
      return this.placeholderResponse();
    }
    let mime: string = 'image/jpeg';
    const lower: string = url.toLowerCase();
    if (lower.indexOf('.png') >= 0) {
      mime = 'image/png';
    } else if (lower.indexOf('.gif') >= 0) {
      mime = 'image/gif';
    } else if (lower.indexOf('.webp') >= 0) {
      mime = 'image/webp';
    } else {
      mime = this.mimeForBuffer(buffer);
    }
    const response: WebResourceResponse = new WebResourceResponse();
    response.setResponseData(buffer);
    response.setResponseMimeType(mime);
    response.setResponseEncoding('binary');
    response.setResponseCode(200);
    return response;
  }

  private mimeForBuffer(buffer: ArrayBuffer): string {
    const bytes: Uint8Array = new Uint8Array(buffer);
    if (bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 &&
      bytes[2] === 0x4e && bytes[3] === 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8) {
      return 'image/jpeg';
    }
    if (bytes.length >= 6 && bytes[0] === 0x47 && bytes[1] === 0x49 &&
      bytes[2] === 0x46) {
      return 'image/gif';
    }
    if (bytes.length >= 12 && bytes[0] === 0x52 && bytes[1] === 0x49 &&
      bytes[2] === 0x46 && bytes[3] === 0x46 && bytes[8] === 0x57 &&
      bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  private async downloadAndReplace(url: string, context: common.UIAbilityContext,
    key: string): Promise<void> {
    if (this.downloading.has(url)) {
      return;
    }
    this.downloading.add(url);
    try {
      const session = await SessionStore.currentSession();
      if (session === null) {
        return;
      }
      const binary = await EtapiService.fetchUrlBinary(session, url);
      await ImageDiskCache.write(context, key, binary.data);
      const base64: string = new util.Base64Helper().encodeToStringSync(
        new Uint8Array(binary.data));
      const dataUri: string = `data:${this.mimeForBuffer(binary.data)};base64,${base64}`;
      const src: string = this.scriptString(url);
      const data: string = this.scriptString(dataUri);
      this.controller.runJavaScript(
        `document.querySelectorAll('img').forEach(function(img){` +
        `if(img.getAttribute('src')===${src}||img.src.indexOf(${src})>=0){img.src=${data};}})`);
    } catch (error) {
      console.error(`WEB_IMAGE_INTERCEPT_FAILED ${url}`);
    } finally {
      this.downloading.delete(url);
    }
  }

  private placeholderResponse(): WebResourceResponse {
    const response: WebResourceResponse = new WebResourceResponse();
    // 1x1 transparent PNG.
    const bytes: Uint8Array = new Uint8Array([
      137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
      0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137,
      0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 252, 207, 192, 240,
      31, 0, 3, 3, 1, 0, 24, 221, 141, 224, 0, 0, 0, 0, 73, 69,
      78, 68, 174, 66, 96, 130
    ]);
    response.setResponseData(bytes.buffer as ArrayBuffer);
    response.setResponseMimeType('image/png');
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
