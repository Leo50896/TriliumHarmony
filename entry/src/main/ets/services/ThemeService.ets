import preferences from '@ohos.data.preferences';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { AppConstants } from '../constants/AppConstants';
import { StateKeys } from '../constants/StateKeys';

/**
 * App-wide theme preference: system / light / dark.
 *
 * The chosen mode is persisted in preferences and the effective color mode is
 * mirrored to AppStorage so NativeSheetView and other reactive components can
 * redraw immediately.
 */
export class ThemeService {
  static readonly SYSTEM: string = 'system';
  static readonly LIGHT: string = 'light';
  static readonly DARK: string = 'dark';

  static installDefault(): void {
    AppStorage.setOrCreate(StateKeys.THEME_MODE, ThemeService.SYSTEM);
    AppStorage.setOrCreate('colorMode', 0);
  }

  static mode(): string {
    const value: string | undefined = AppStorage.get<string>(StateKeys.THEME_MODE);
    return value === ThemeService.LIGHT || value === ThemeService.DARK
      ? value : ThemeService.SYSTEM;
  }

  static isDark(): boolean {
    return AppStorage.get<number>('colorMode') === 0;
  }

  static async initialize(context: common.UIAbilityContext): Promise<void> {
    ThemeService.installDefault();
    let mode: string = ThemeService.SYSTEM;
    try {
      const store: preferences.Preferences =
        await preferences.getPreferences(context, { name: AppConstants.PREF_THEME_STORE_NAME });
      const value: preferences.ValueType = await store.get(AppConstants.KEY_THEME_MODE, ThemeService.SYSTEM);
      if (typeof value === 'string') {
        mode = ThemeService.normalize(value);
      }
    } catch (error) {
      mode = ThemeService.SYSTEM;
    }
    ThemeService.apply(context, mode);
  }

  static async setMode(context: common.UIAbilityContext, mode: string): Promise<void> {
    const normalized: string = ThemeService.normalize(mode);
    AppStorage.setOrCreate(StateKeys.THEME_MODE, normalized);
    ThemeService.apply(context, normalized);
    try {
      const store: preferences.Preferences =
        await preferences.getPreferences(context, { name: AppConstants.PREF_THEME_STORE_NAME });
      await store.put(AppConstants.KEY_THEME_MODE, normalized);
      await store.flush();
    } catch (error) {
      // The in-memory theme change must still apply if persistence fails.
    }
  }

  static apply(context: common.UIAbilityContext, mode: string): void {
    const normalized: string = ThemeService.normalize(mode);
    AppStorage.setOrCreate(StateKeys.THEME_MODE, normalized);
    try {
      if (normalized === ThemeService.LIGHT) {
        context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
        AppStorage.setOrCreate('colorMode', 1);
      } else if (normalized === ThemeService.DARK) {
        context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
        AppStorage.setOrCreate('colorMode', 0);
      } else {
        context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
        AppStorage.setOrCreate('colorMode', context.config.colorMode);
      }
    } catch (error) {
      AppStorage.setOrCreate('colorMode', context.config.colorMode);
    }
  }

  static normalize(mode: string): string {
    if (mode === ThemeService.LIGHT || mode === ThemeService.DARK) {
      return mode;
    }
    return ThemeService.SYSTEM;
  }
}
