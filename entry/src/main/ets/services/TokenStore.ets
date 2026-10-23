import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { AuthSession } from '../models/AuthModels';
import { AppConstants } from '../constants/AppConstants';
import { MockConfig } from '../constants/MockConfig';

/**
 * Minimal persistence for the auth session.
 *
 * `preferences` is used because the requirement explicitly asks for it. A
 * production build should additionally protect the refresh token with HUKS
 * (Universal Keystore) or secure storage; preferences alone is not encrypted.
 */
export class TokenStore {
  private static async getStore(context: common.UIAbilityContext): Promise<preferences.Preferences> {
    try {
      return await preferences.getPreferences(context, { name: AppConstants.PREF_STORE_NAME });
    } catch (error) {
      throw new Error('Failed to open the auth preferences store');
    }
  }

  static async saveSession(context: common.UIAbilityContext, session: AuthSession): Promise<void> {
    try {
      const store: preferences.Preferences = await TokenStore.getStore(context);
      await store.put(AppConstants.KEY_ACCESS_TOKEN, session.accessToken);
      await store.put(AppConstants.KEY_REFRESH_TOKEN, session.refreshToken);
      await store.put(AppConstants.KEY_EXPIRES_AT, session.expiresAt);
      await store.put(AppConstants.KEY_USERNAME, session.username);
      await store.put(AppConstants.KEY_SERVER_URL, session.serverUrl);
      await store.flush();
    } catch (error) {
      throw new Error('Failed to persist the auth session');
    }
  }

  static async loadSession(context: common.UIAbilityContext): Promise<AuthSession | null> {
    try {
      const store: preferences.Preferences = await TokenStore.getStore(context);
      const tokenValue: preferences.ValueType = await store.get(AppConstants.KEY_ACCESS_TOKEN, '');
      const token: string = typeof tokenValue === 'string' ? tokenValue : '';
      if (token.length === 0) {
        return null;
      }

      const expiresValue: preferences.ValueType = await store.get(AppConstants.KEY_EXPIRES_AT, 0);
      const expiresAt: number = typeof expiresValue === 'number' ? expiresValue : 0;
      const refreshValue: preferences.ValueType = await store.get(AppConstants.KEY_REFRESH_TOKEN, '');
      const refreshToken: string = typeof refreshValue === 'string' ? refreshValue : '';
      const userValue: preferences.ValueType = await store.get(AppConstants.KEY_USERNAME, '');
      const username: string = typeof userValue === 'string' ? userValue : 'trilium';
      const serverValue: preferences.ValueType = await store.get(AppConstants.KEY_SERVER_URL, '');
      const serverUrl: string = typeof serverValue === 'string' && serverValue.length > 0
        ? serverValue : MockConfig.DEFAULT_SERVER_URL;

      return new AuthSession(token, refreshToken, expiresAt, username, serverUrl);
    } catch (error) {
      throw new Error('Failed to read the auth session');
    }
  }

  static isSessionValid(session: AuthSession | null): boolean {
    if (session === null || session.accessToken.length === 0) {
      return false;
    }
    return session.expiresAt - AppConstants.TOKEN_EXPIRY_SKEW_MS > Date.now();
  }

  static async getValidSession(context: common.UIAbilityContext): Promise<AuthSession | null> {
    const session: AuthSession | null = await TokenStore.loadSession(context);
    if (TokenStore.isSessionValid(session)) {
      return session;
    }
    if (session !== null) {
      await TokenStore.clearSession(context);
    }
    return null;
  }

  static async clearSession(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await TokenStore.getStore(context);
      await store.clear();
      await store.flush();
    } catch (error) {
      throw new Error('Failed to clear the auth session');
    }
  }
}
