import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { ThemeService } from '../services/ThemeService';

const DOMAIN: number = 0x0000;
const TAG: string = 'TriliumAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    ThemeService.installDefault();
    AppStorage.setOrCreate('colorMode', this.context.config.colorMode);
    hilog.info(DOMAIN, TAG, 'Ability created');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    AppStorage.setOrCreate('colorMode', newConfig.colorMode);
    hilog.info(DOMAIN, TAG, 'Color mode updated: %{public}d', newConfig.colorMode);
  }

  onForeground(): void {
    const tick: number = AppStorage.get<number>('app.foregroundTick') ?? 0;
    AppStorage.setOrCreate('app.foregroundTick', tick + 1);
  }

  onBackground(): void {
    const tick: number = AppStorage.get<number>('app.backgroundTick') ?? 0;
    AppStorage.setOrCreate('app.backgroundTick', tick + 1);
  }

  private systemBarBg(): string {
    const mode: string = ThemeService.mode();
    const dark: boolean = mode === ThemeService.DARK ||
      (mode === ThemeService.SYSTEM &&
        this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    return dark ? '#0D131C' : '#F7F8FA';
  }

  private systemBarContentColor(): string {
    const mode: string = ThemeService.mode();
    const dark: boolean = mode === ThemeService.DARK ||
      (mode === ThemeService.SYSTEM &&
        this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    return dark ? '#FFFFFF' : '#000000';
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    ThemeService.initialize(this.context).then(() => {
      try {
        const mainWindow: window.Window = windowStage.getMainWindowSync();
        mainWindow.setWindowSystemBarProperties({
          statusBarColor: this.systemBarBg(),
          navigationBarColor: this.systemBarBg(),
          statusBarContentColor: this.systemBarContentColor(),
          navigationBarContentColor: this.systemBarContentColor()
        });
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Unable to style system bars: %{public}s', JSON.stringify(error));
      }

      windowStage.loadContent('pages/Index', (err) => {
        if (err.code) {
          hilog.error(DOMAIN, TAG, 'Failed to load Index: %{public}s', JSON.stringify(err));
          return;
        }
        hilog.info(DOMAIN, TAG, 'Index loaded');
      });
    }).catch((error: Error) => {
      hilog.warn(DOMAIN, TAG, 'Unable to initialize theme: %{public}s', JSON.stringify(error));
      windowStage.loadContent('pages/Index');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Window stage destroyed');
  }
}
