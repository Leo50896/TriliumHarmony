import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { AppIcon } from '../components/AppIcon';
import { ExternalLinkLauncher } from '../services/ExternalLinkLauncher';

const SOURCE_REPOSITORY: string = 'https://github.com/Leo50896/TriliumHarmony';
const COPYRIGHT_HOLDER: string = 'Leo50896';

/**
 * AGPL-3.0 license and corresponding-source entry.
 */
@Component
export struct LicenseView {
  onBack: () => void = () => {};

  @State private licenseText: string = '';
  @State private loading: boolean = true;

  aboutToAppear(): void {
    this.loadLicense();
  }

  private async loadLicense(): Promise<void> {
    try {
      const host: common.Context | undefined = this.getUIContext().getHostContext();
      if (host === undefined) {
        this.loading = false;
        return;
      }
      const bytes: Uint8Array = await host.resourceManager.getRawFileContent('agpl-3.0.txt');
      this.licenseText = util.TextDecoder.create('utf-8').decodeToString(bytes);
    } catch (error) {
      this.licenseText = '无法读取 AGPL-3.0 协议文件。';
    }
    this.loading = false;
  }

  private async openSource(): Promise<void> {
    const host: common.Context | undefined = this.getUIContext().getHostContext();
    if (host !== undefined) {
      await ExternalLinkLauncher.open(host as common.UIAbilityContext, SOURCE_REPOSITORY);
    }
  }

  build() {
    Column() {
      Row({ space: 4 }) {
        Stack({ alignContent: Alignment.Center }) {
          AppIcon({
            icon: $r('app.media.ic_back'),
            iconSize: 21,
            tint: $r('app.color.text_primary')
          })
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .onClick(this.onBack)
        Text('开源许可与源码')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 14 })

      Scroll() {
        Column({ space: 14 }) {
          Column({ space: 8 }) {
            Text('AGPL-3.0')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text(`本应用基于 Trilium 构建 (Copyright (C) 2026 ${COPYRIGHT_HOLDER})。遵循 AGPL-3.0 协议。`)
              .fontSize(12.5)
              .lineHeight(19)
              .fontColor($r('app.color.text_secondary'))
            Button('获取本应用完整源码')
              .width('100%')
              .height(42)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .backgroundColor($r('app.color.primary'))
              .fontColor($r('app.color.text_on_primary'))
              .borderRadius(12)
              .margin({ top: 4 })
              .onClick(() => {
                this.openSource();
              })
          }
          .width('100%')
          .padding(16)
          .alignItems(HorizontalAlign.Start)
          .backgroundColor($r('app.color.bg_surface'))
          .borderRadius(16)
          .border({ width: 1, color: $r('app.color.border') })

          Text('GNU AFFERO GENERAL PUBLIC LICENSE')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')

          if (this.loading) {
            LoadingProgress()
              .width(28)
              .height(28)
              .color($r('app.color.primary'))
              .margin({ top: 20 })
          } else {
            Text(this.licenseText)
              .width('100%')
              .fontFamily('monospace')
              .fontSize(12)
              .lineHeight(18)
              .fontColor($r('app.color.text_primary'))
              .copyOption(CopyOptions.LocalDevice)
              .padding({ bottom: 30 })
          }
        }
        .width('100%')
        .constraintSize({ maxWidth: 760 })
        .padding({ left: 16, right: 16, top: 4 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.None)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }
}
