import { AppIcon } from './AppIcon';

@Component
export struct SettingsNavRow {
  @Prop icon: Resource = $r('app.media.ic_server');
  @Prop title: string = '';
  @Prop value: string = '';
  @Prop showChevron: boolean = true;
  @Prop showStatusDot: boolean = false;
  @Prop monospaceValue: boolean = false;
  onTap: () => void = () => {};

  build() {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        AppIcon({
          icon: this.icon,
          iconSize: 18,
          tint: $r('app.color.primary_text')
        })
      }
      .width(34)
      .height(34)
      .borderRadius(9)
      .backgroundColor($r('app.color.primary_soft'))

      Text(this.title)
        .layoutWeight(1)
        .fontSize(14.5)
        .fontColor($r('app.color.text_primary'))

      if (this.value.length > 0) {
        Text(this.value)
          .fontSize(12.5)
          .fontColor(this.showStatusDot ? $r('app.color.text_secondary') : $r('app.color.text_tertiary'))
          .fontFamily(this.monospaceValue ? 'monospace' : 'HarmonyOS Sans')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 190 })
      }
      if (this.showStatusDot) {
        Row()
          .width(6)
          .height(6)
          .borderRadius(3)
          .backgroundColor($r('app.color.success'))
          .margin({ left: 2 })
      }
      if (this.showChevron) {
        AppIcon({
          icon: $r('app.media.ic_chevron_right'),
          iconSize: 14,
          tint: $r('app.color.text_tertiary'),
          opacityValue: 0.7
        })
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 13 })
    .onClick(this.onTap)
  }
}

@Component
export struct SettingsToggleRow {
  @Prop icon: Resource = $r('app.media.ic_face');
  @Prop title: string = '';
  @Link checked: boolean;

  build() {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        AppIcon({
          icon: this.icon,
          iconSize: 18,
          tint: $r('app.color.primary_text')
        })
      }
      .width(34)
      .height(34)
      .borderRadius(9)
      .backgroundColor($r('app.color.primary_soft'))

      Text(this.title)
        .layoutWeight(1)
        .fontSize(14.5)
        .fontColor($r('app.color.text_primary'))

      Toggle({ type: ToggleType.Switch, isOn: this.checked })
        .selectedColor($r('app.color.primary'))
        .switchPointColor($r('app.color.text_on_primary'))
        .onChange((isOn: boolean) => {
          this.checked = isOn;
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 13 })
  }
}

@Component
export struct SettingsSliderRow {
  @Prop icon: Resource = $r('app.media.ic_font');
  @Prop title: string = '';
  @Link value: number;
  onChanged: (value: number) => void = () => {};

  build() {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        AppIcon({
          icon: this.icon,
          iconSize: 18,
          tint: $r('app.color.primary_text')
        })
      }
      .width(34)
      .height(34)
      .borderRadius(9)
      .backgroundColor($r('app.color.primary_soft'))

      Text(this.title)
        .fontSize(14.5)
        .fontColor($r('app.color.text_primary'))

      Slider({
        value: this.value,
        min: 12,
        max: 22,
        step: 1,
        style: SliderStyle.InSet
      })
        .layoutWeight(1)
        .blockColor($r('app.color.text_on_primary'))
        .selectedColor($r('app.color.primary'))
        .trackColor($r('app.color.bg_surface_alt'))
        .onChange((value: number) => {
          this.value = value;
          this.onChanged(value);
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 13 })
  }
}
