import { webview } from '@kit.ArkWeb';

class SheetBridge {
  onReady: () => void = () => {};
  onJson: (json: string) => void = () => {};
  onAlert: (message: string) => void = () => {};

  ready(value: string): void {
    if (value.length > 0) {
      this.onReady();
    }
  }

  json(value: string): void {
    if (value.length > 0) {
      this.onJson(value);
    }
  }

  showAlert(message: string): void {
    this.onAlert(message);
  }
}

@Component
export struct SheetWebView {
  @Prop @Watch('onContentChanged') content: string = '';
  @Prop @Watch('onReadOnlyChanged') readOnly: boolean = true;
  @Prop @Watch('onSaveTick') saveTick: number = 0;
  onJson: (json: string) => void = () => {};
  onAlert: (message: string) => void = () => {};
  @State private ready: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: SheetBridge = new SheetBridge();

  aboutToAppear(): void {
    this.bridge.onReady = () => {
      this.inject();
    };
    this.bridge.onJson = (json: string) => {
      this.onJson(json);
    };
    this.bridge.onAlert = (message: string) => {
      this.onAlert(message);
    };
  }

  private inject(): void {
    if (!this.ready) {
      return;
    }
    const json: string = JSON.stringify(this.content).replace(/</g, '\\u003c');
    this.controller.runJavaScript(`window.NativeSheet.render(${json})`);
  }

  private onContentChanged(): void {
    this.inject();
  }

  private onReadOnlyChanged(): void {
    if (!this.ready) {
      return;
    }
    this.controller.runJavaScript(`window.NativeSheet.setReadOnly(${this.readOnly})`);
  }

  private onSaveTick(): void {
    if (!this.ready || this.saveTick === 0) {
      return;
    }
    this.controller.runJavaScript('window.NativeSheet.getAndSend()');
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (!this.ready) {
        LoadingProgress()
          .width(26)
          .height(26)
          .color('#0A84FF')
      }
      Web({ src: $rawfile('sheet.html'), controller: this.controller })
        .width('100%')
        .height('100%')
        .backgroundColor('#0D131C')
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .javaScriptProxy({
          object: this.bridge,
          name: 'NativeSheetBridge',
          methodList: ['ready', 'json', 'showAlert'],
          controller: this.controller
        })
        .onPageEnd(() => {
          this.ready = true;
          this.inject();
        })
    }
    .width('100%')
    .height(720)
  }
}
