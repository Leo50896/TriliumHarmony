import http from '@ohos.net.http';
import image from '@ohos.multimedia.image';
import { common } from '@kit.AbilityKit';
import { HttpService } from '../services/HttpService';
import { CachedImage, ImageDiskCache } from '../services/ImageDiskCache';

/**
 * Full-screen image viewer.
 *
 * Gestures:
 *   - pinch: 0.5x .. 3x
 *   - one-finger pan when zoomed in
 *   - double tap: 2.5x / reset
 *   - single tap: close (delayed so the second tap of a double tap can cancel it)
 */
@Component
export struct ImagePreview {
  @Prop pixelMap: image.PixelMap | null = null;
  @Prop src: string = '';
  @Prop alt: string = '';
  @StorageProp('auth.token') private accessToken: string = '';
  @StorageProp('auth.serverUrl') private serverUrl: string = '';
  onClose: () => void = () => {};

  @State private loadedMap: image.PixelMap | null = null;
  @State private isImageLoading: boolean = false;
  @State private imageLoadError: string = '';
  @State private scaleValue: number = 1;
  @State private offsetX: number = 0;
  @State private offsetY: number = 0;

  private viewWidth: number = 360;
  private viewHeight: number = 760;
  private pinchStartScale: number = 1;
  private panStartX: number = 0;
  private panStartY: number = 0;
  private lastTapAt: number = 0;
  private closeTimer: number = -1;
  private loadSequence: number = 0;

  aboutToAppear(): void {
    if (this.src.length > 0) {
      this.loadPreviewImage();
    }
  }

  private normalizeServer(): string {
    let value: string = this.serverUrl.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  private hostContext(): common.UIAbilityContext | null {
    const context: common.Context | undefined = this.getUIContext().getHostContext();
    return context === undefined ? null : context as common.UIAbilityContext;
  }

  private resolveUrl(): string {
    const source: string = this.src.trim();
    if (/^https?:\/\//i.test(source)) {
      return source;
    }
    if (source.startsWith('data:')) {
      return '';
    }
    const server: string = this.normalizeServer();
    let path: string = source;
    while (path.startsWith('/') || path.startsWith('./')) {
      path = path.startsWith('/') ? path.substring(1) : path.substring(2);
    }
    const attachmentMatch: RegExpMatchArray | null =
      path.match(/api\/attachments\/([^/?#]+)/i);
    if (attachmentMatch !== null) {
      return `${server}/etapi/attachments/${encodeURIComponent(attachmentMatch[1])}/content`;
    }
    const imageNoteMatch: RegExpMatchArray | null =
      path.match(/api\/images\/([^/?#]+)/i);
    if (imageNoteMatch !== null) {
      return `${server}/etapi/notes/${encodeURIComponent(imageNoteMatch[1])}/content`;
    }
    return `${server}/${path}`;
  }

  private async loadPreviewImage(): Promise<void> {
    const url: string = this.resolveUrl();
    if (url.length === 0) {
      this.imageLoadError = '图片地址无效';
      return;
    }
    const sequence: number = ++this.loadSequence;
    this.isImageLoading = true;
    this.imageLoadError = '';
    const context: common.UIAbilityContext | null = this.hostContext();
    let cacheKey: string = '';
    if (context !== null) {
      try {
        cacheKey = await ImageDiskCache.keyFor(this.serverUrl, this.src);
        if (sequence !== this.loadSequence) {
          return;
        }
        const cached: CachedImage | null = await ImageDiskCache.read(context, cacheKey);
        if (sequence !== this.loadSequence) {
          return;
        }
        if (cached !== null) {
          this.loadedMap = cached.pixelMap;
          this.isImageLoading = false;
          return;
        }
      } catch (error) {
        cacheKey = '';
      }
    }
    try {
      const response: http.HttpResponse = await HttpService.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'Authorization': this.accessToken,
          'Accept': 'image/*'
        },
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 10000,
        readTimeout: 20000
      });
      if (sequence !== this.loadSequence) {
        return;
      }
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`IMAGE_HTTP_${response.responseCode}`);
      }
      const buffer: ArrayBuffer = response.result as ArrayBuffer;
      if (context !== null && cacheKey.length > 0) {
        ImageDiskCache.write(context, cacheKey, buffer).catch(() => {
          // Disk cache is best-effort.
        });
      }
      const source: image.ImageSource = image.createImageSource(buffer);
      try {
        const pixelMap: image.PixelMap = await source.createPixelMap();
        if (sequence === this.loadSequence) {
          this.loadedMap = pixelMap;
        }
      } finally {
        await source.release();
      }
    } catch (error) {
      if (sequence === this.loadSequence) {
        this.imageLoadError = '图片加载失败';
        if (error instanceof Error && error.message === 'AUTH_401') {
          this.onClose();
        }
      }
    } finally {
      if (sequence === this.loadSequence) {
        this.isImageLoading = false;
      }
    }
  }

  private clamp(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, value));
  }

  private maxOffsetX(): number {
    return Math.max(0, (this.viewWidth * (this.scaleValue - 1)) / 2);
  }

  private maxOffsetY(): number {
    return Math.max(0, (this.viewHeight * (this.scaleValue - 1)) / 2);
  }

  private clampOffsets(): void {
    this.offsetX = this.clamp(this.offsetX, -this.maxOffsetX(), this.maxOffsetX());
    this.offsetY = this.clamp(this.offsetY, -this.maxOffsetY(), this.maxOffsetY());
  }

  private resetWithAnimation(): void {
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.scaleValue = 1;
      this.offsetX = 0;
      this.offsetY = 0;
    });
  }

  private toggleZoom(): void {
    if (this.scaleValue > 1.05) {
      this.resetWithAnimation();
      return;
    }
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.scaleValue = 2.5;
      this.offsetX = 0;
      this.offsetY = 0;
    });
  }

  private handleTap(): void {
    const now: number = Date.now();
    if (now - this.lastTapAt < 650) {
      if (this.closeTimer >= 0) {
        clearTimeout(this.closeTimer);
        this.closeTimer = -1;
      }
      this.lastTapAt = 0;
      this.toggleZoom();
      return;
    }
    this.lastTapAt = now;
    if (this.closeTimer >= 0) {
      clearTimeout(this.closeTimer);
    }
    this.closeTimer = setTimeout(() => {
      if (Date.now() - this.lastTapAt >= 620) {
        this.onClose();
      }
    }, 700);
  }

  private handlePinchEnd(): void {
    if (this.scaleValue < 1) {
      this.resetWithAnimation();
      return;
    }
    if (this.scaleValue > 3) {
      this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
        this.scaleValue = 3;
      });
    }
    this.clampOffsets();
  }

  private handlePanEnd(): void {
    this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, () => {
      this.clampOffsets();
    });
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.loadedMap !== null) {
        Image(this.loadedMap)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .scale({ x: this.scaleValue, y: this.scaleValue })
          .translate({ x: this.offsetX, y: this.offsetY })
      } else if (this.pixelMap !== null) {
        Image(this.pixelMap)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .scale({ x: this.scaleValue, y: this.scaleValue })
          .translate({ x: this.offsetX, y: this.offsetY })
      } else if (this.isImageLoading) {
        LoadingProgress()
          .width(26)
          .height(26)
          .color($r('app.color.white'))
      } else {
        Text(this.imageLoadError.length > 0 ? this.imageLoadError : '图片不可用')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }

      Row() {
        Blank()
        Text('×')
          .fontSize(26)
          .fontColor($r('app.color.white'))
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .backgroundColor($r('app.color.overlay_scrim'))
          .borderRadius(20)
          .onClick(() => {
            this.onClose();
          })
      }
      .width('100%')
      .padding({ top: 48, left: 18, right: 18 })
      .position({ x: 0, y: 0 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.black'))
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.viewWidth = parseFloat(newArea.width.toString());
      this.viewHeight = parseFloat(newArea.height.toString());
      this.clampOffsets();
    })
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        PinchGesture({ fingers: 2 })
          .onActionStart(() => {
            this.pinchStartScale = this.scaleValue;
          })
          .onActionUpdate((event: GestureEvent) => {
            this.scaleValue = this.clamp(this.pinchStartScale * event.scale, 0.5, 3);
            this.clampOffsets();
          })
          .onActionEnd(() => {
            this.handlePinchEnd();
          }),
        PanGesture({ fingers: 1, direction: PanDirection.All, distance: 4 })
          .onActionStart(() => {
            this.panStartX = this.offsetX;
            this.panStartY = this.offsetY;
          })
          .onActionUpdate((event: GestureEvent) => {
            if (this.scaleValue <= 1.01) {
              return;
            }
            this.offsetX = this.panStartX + event.offsetX;
            this.offsetY = this.panStartY + event.offsetY;
            this.clampOffsets();
          })
          .onActionEnd(() => {
            this.handlePanEnd();
          }),
        TapGesture({ count: 1 })
          .onAction(() => {
            this.handleTap();
          })
      )
    )
  }
}
