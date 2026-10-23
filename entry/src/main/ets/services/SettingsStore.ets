import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { StateKeys } from '../constants/StateKeys';

/**
 * Durable, user-visible app settings (sync cadence and reading font size).
 * Values are mirrored into AppStorage so Index/EditorView react immediately.
 */
export class SettingsStore {
  private static readonly FILE: string = 'trilium_settings';
  private static readonly KEY_SYNC: string = 'syncIntervalSeconds';
  private static readonly KEY_FONT: string = 'readerFontSize';
  private static readonly KEY_FACE_UNLOCK: string = 'faceUnlockEnabled';
  private static store: preferences.Preferences | null = null;

  static async initialize(context: common.UIAbilityContext): Promise<void> {
    try {
      if (SettingsStore.store === null) {
        SettingsStore.store = await preferences.getPreferences(context, SettingsStore.FILE);
      }
      const syncValue: number = await SettingsStore.store.get(SettingsStore.KEY_SYNC, 30) as number;
      const fontValue: number = await SettingsStore.store.get(SettingsStore.KEY_FONT, 16) as number;
      const faceValue: boolean = await SettingsStore.store.get(SettingsStore.KEY_FACE_UNLOCK, false) as boolean;
      AppStorage.setOrCreate(StateKeys.SYNC_INTERVAL, syncValue);
      AppStorage.setOrCreate(StateKeys.READER_FONT_SIZE, fontValue);
      AppStorage.setOrCreate(StateKeys.BIOMETRIC_UNLOCK, faceValue);
    } catch (error) {
      AppStorage.setOrCreate(StateKeys.SYNC_INTERVAL, 30);
      AppStorage.setOrCreate(StateKeys.READER_FONT_SIZE, 16);
      AppStorage.setOrCreate(StateKeys.BIOMETRIC_UNLOCK, false);
    }
  }

  static async setFaceUnlock(context: common.UIAbilityContext, enabled: boolean): Promise<void> {
    AppStorage.setOrCreate(StateKeys.BIOMETRIC_UNLOCK, enabled);
    try {
      await SettingsStore.ensure(context);
      await SettingsStore.store?.put(SettingsStore.KEY_FACE_UNLOCK, enabled);
      await SettingsStore.store?.flush();
    } catch (error) {
      // AppStorage still carries the new value for this session.
    }
  }

  static async setSyncInterval(context: common.UIAbilityContext, seconds: number): Promise<void> {
    AppStorage.setOrCreate(StateKeys.SYNC_INTERVAL, seconds);
    try {
      await SettingsStore.ensure(context);
      await SettingsStore.store?.put(SettingsStore.KEY_SYNC, seconds);
      await SettingsStore.store?.flush();
    } catch (error) {
      // AppStorage still carries the new value for this session.
    }
  }

  static async setReaderFontSize(context: common.UIAbilityContext, size: number): Promise<void> {
    AppStorage.setOrCreate(StateKeys.READER_FONT_SIZE, size);
    try {
      await SettingsStore.ensure(context);
      await SettingsStore.store?.put(SettingsStore.KEY_FONT, size);
      await SettingsStore.store?.flush();
    } catch (error) {
      // AppStorage still carries the new value for this session.
    }
  }

  private static async ensure(context: common.UIAbilityContext): Promise<void> {
    if (SettingsStore.store === null) {
      SettingsStore.store = await preferences.getPreferences(context, SettingsStore.FILE);
    }
  }
}
