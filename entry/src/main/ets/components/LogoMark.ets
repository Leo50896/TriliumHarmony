/**
 * The Trilium brand mark used inside the app. It reuses the same official
 * three-leaf artwork as the launcher icon so the splash, login page and drawer
 * stay visually consistent with the installed app.
 */
@Component
export struct LogoMark {
  @Prop markSize: number = 76;
  @Prop showGlow: boolean = true;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.showGlow) {
        Row()
          .width(this.markSize * 1.55)
          .height(this.markSize * 1.55)
          .borderRadius(999)
          .backgroundColor($r('app.color.logo_shadow'))
          .opacity(0.14)
          .blur(32)
      }
      Image($r('app.media.app_icon'))
        .width(this.markSize)
        .height(this.markSize)
        .objectFit(ImageFit.Cover)
        .borderRadius(this.markSize * 0.27)
        .clip(true)
        .interpolation(ImageInterpolation.High)
        .draggable(false)
        .shadow({
          radius: this.markSize * 0.22,
          color: $r('app.color.shadow'),
          offsetX: 0,
          offsetY: this.markSize * 0.08
        })
    }
    .width(this.markSize * 1.7)
    .height(this.markSize * 1.7)
  }
}
