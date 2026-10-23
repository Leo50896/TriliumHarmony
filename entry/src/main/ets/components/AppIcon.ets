/**
 * A tintable SVG icon wrapper. Every media icon is authored as a white glyph,
 * which lets light and muted variants share one asset.
 */
@Component
export struct AppIcon {
  @Prop icon: Resource = $r('app.media.ic_doc');
  @Prop iconSize: number = 20;
  @Prop tint: Resource = $r('app.color.text_secondary');
  @Prop opacityValue: number = 1;

  build() {
    Image(this.icon)
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .fillColor(this.tint)
      .opacity(this.opacityValue)
      .draggable(false)
      .interpolation(ImageInterpolation.High)
  }
}
