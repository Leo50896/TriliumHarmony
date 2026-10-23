import http from '@ohos.net.http';
import image from '@ohos.multimedia.image';
import { common } from '@kit.AbilityKit';
import { HttpService } from '../services/HttpService';
import { CachedImage, ImageDiskCache } from '../services/ImageDiskCache';
import { ImagePreview } from './ImagePreview';

/**
 * Trilium content image.
 *
 * Trilium image `src` values usually point at an internal endpoint such as
 * `api/attachments/<id>/image/<name>` or `api/images/<noteId>/<name>`, which
 * needs the ETAPI token. Those URLs are translated to the corresponding ETAPI
 * content endpoint and fetched with the Authorization header. External URLs
 * are fetched as-is.
 */
@Component
export struct TriliumImage {
  @Prop @Watch('onSourceChanged') src: string = '';
  @Prop alt: string = '';
  @Prop widthPercent: number = 0;
  @StorageProp('auth.token') @Watch('onAuthChanged') private accessToken: string = '';
  @StorageProp('auth.serverUrl') @Watch('onAuthChanged') private serverUrl: string = '';

  @State private pixelMap: image.PixelMap | null = null;
  @State private previewPixelMap: image.PixelMap | null = null;
  @State private imageRatio: number = 1;
  @State private isLoading: boolean = false;
  @State private errorMessage: string = '';
  @State private showPreview: boolean = false;
  private loadSequence: number = 0;

  aboutToAppear(): void {
    this.load();
  }

  private onSourceChanged(): void {
    this.showPreview = false;
    this.previewPixelMap = null;
    this.load();
  }

  private onAuthChanged(): void {
    if (this.src.length > 0) {
      this.load();
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

  private async load(): Promise<void> {
    const sequence: number = ++this.loadSequence;
    this.pixelMap = null;
    this.errorMessage = '';
    const url: string = this.resolveUrl();
    if (url.length === 0 || this.serverUrl.trim().length === 0) {
      this.errorMessage = '图片地址无效';
      return;
    }

    this.isLoading = true;
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
          this.imageRatio = cached.ratio;
          this.pixelMap = cached.pixelMap;
          this.isLoading = false;
          return;
        }
      } catch (error) {
        // Cache failure must never block the network path.
        cacheKey = '';
      }
    }

    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: {
          'Authorization': this.accessToken,
          'Accept': 'image/*'
        },
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 10000,
        readTimeout: 20000
      };
      const response: http.HttpResponse = await HttpService.request(url, options);
      if (sequence !== this.loadSequence) {
        return;
      }
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`IMAGE_HTTP_${response.responseCode}`);
      }
      const buffer: ArrayBuffer = response.result as ArrayBuffer;
      if (context !== null && cacheKey.length > 0) {
        ImageDiskCache.write(context as common.UIAbilityContext, cacheKey, buffer).catch(() => {
          // Disk cache is best-effort.
        });
      }
      const source: image.ImageSource = image.createImageSource(buffer);
      try {
        const info: image.ImageInfo = await source.getImageInfo();
        if (info.size.width > 0 && info.size.height > 0) {
          this.imageRatio = info.size.width / info.size.height;
        }
        const pixelMap: image.PixelMap = await source.createPixelMap();
        if (sequence === this.loadSequence) {
          this.pixelMap = pixelMap;
        }
      } finally {
        await source.release();
      }
    } catch (error) {
      if (sequence === this.loadSequence) {
        this.errorMessage = '图片加载失败';
      }
    } finally {
      if (sequence === this.loadSequence) {
        this.isLoading = false;
      }
    }
  }

  private imageWidth(): string {
    if (this.widthPercent > 0 && this.widthPercent <= 100) {
      return `${this.widthPercent}%`;
    }
    return '100%';
  }

  build() {
    Column({ space: 6 }) {
      if (this.isLoading) {
        Row() {
          LoadingProgress()
            .width(22)
            .height(22)
            .color($r('app.color.primary'))
        }
        .width('100%')
        .height(80)
        .justifyContent(FlexAlign.Center)
      } else if (this.errorMessage.length > 0) {
        Row() {
          Text(this.errorMessage)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .height(56)
        .justifyContent(FlexAlign.Center)
      } else if (this.pixelMap !== null) {
        Row() {
          Image(this.pixelMap)
            .width(this.imageWidth())
            .aspectRatio(this.imageRatio)
            .objectFit(ImageFit.Contain)
            .borderRadius(8)
            .interpolation(ImageInterpolation.High)
            .onClick(() => {
              if (this.pixelMap !== null) {
                this.previewPixelMap = this.pixelMap;
                this.showPreview = true;
              }
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }

      if (this.alt.length > 0) {
        Text(this.alt)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .textAlign(TextAlign.Center)
          .width('100%')
      }
    }
    .width('100%')
    .margin({ top: 14, bottom: 14 })
    .bindContentCover(this.showPreview, this.PreviewContent, {
      modalTransition: ModalTransition.DEFAULT
    })
  }

  @Builder
  private PreviewContent() {
    ImagePreview({
      pixelMap: this.previewPixelMap,
      src: this.src,
      alt: this.alt,
      onClose: () => {
        this.showPreview = false;
        this.previewPixelMap = null;
      }
    })
  }
}
