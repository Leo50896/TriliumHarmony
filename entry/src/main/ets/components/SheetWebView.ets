import { webview } from '@kit.ArkWeb';

class SheetBridge {
  onReady: () => void = () => {};

  ready(value: string): void {
    if (value.length > 0) {
      this.onReady();
    }
  }
}

@Component
export struct SheetWebView {
  @Prop @Watch('onContentChanged') content: string = '';
  @State private ready: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: SheetBridge = new SheetBridge();

  aboutToAppear(): void {
    this.bridge.onReady = () => {
      this.inject();
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
          methodList: ['ready'],
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
