import { common } from '@kit.AbilityKit';
import { AuthSession } from '../models/AuthModels';
import { StateKeys } from '../constants/StateKeys';
import { ReadingPositionStore } from './ReadingPositionStore';
import { TokenStore } from './TokenStore';

/**
 * Single owner of the in-memory session and its AppStorage mirror.
 *
 * preferences remains the durable copy; AppStorage is the reactive copy that
 * SideDrawer, EditorView, TriliumImage and ImagePreview subscribe to.
 */
export class SessionStore {
  private static context: common.UIAbilityContext | null = null;

  static installDefaults(): void {
    AppStorage.setOrCreate(StateKeys.AUTH_TOKEN, '');
    AppStorage.setOrCreate(StateKeys.AUTH_REFRESH_TOKEN, '');
    AppStorage.setOrCreate(StateKeys.AUTH_EXPIRES_AT, 0);
    AppStorage.setOrCreate(StateKeys.AUTH_USERNAME, '');
    AppStorage.setOrCreate(StateKeys.AUTH_SERVER_URL, '');
    AppStorage.setOrCreate(StateKeys.AUTH_LOGGED_IN, false);
    AppStorage.setOrCreate(StateKeys.SELECTED_NOTE_ID, '');
    AppStorage.setOrCreate(StateKeys.SELECTED_NOTE_TITLE, '');
    AppStorage.setOrCreate(StateKeys.OPEN_GLOBAL_SEARCH, false);
  }

  static async initialize(context: common.UIAbilityContext): Promise<AuthSession | null> {
    SessionStore.context = context;
    SessionStore.installDefaults();
    try {
      const session: AuthSession | null = await TokenStore.getValidSession(context);
      if (session === null) {
        SessionStore.clearValues();
        return null;
      }
      SessionStore.applySession(session);
      return session;
    } catch (error) {
      SessionStore.clearValues();
      return null;
    }
  }

  static applySession(session: AuthSession): void {
    AppStorage.setOrCreate(StateKeys.AUTH_TOKEN, session.accessToken);
    AppStorage.setOrCreate(StateKeys.AUTH_REFRESH_TOKEN, session.refreshToken);
    AppStorage.setOrCreate(StateKeys.AUTH_EXPIRES_AT, session.expiresAt);
    AppStorage.setOrCreate(StateKeys.AUTH_USERNAME, session.username);
    AppStorage.setOrCreate(StateKeys.AUTH_SERVER_URL, session.serverUrl);
    AppStorage.setOrCreate(StateKeys.AUTH_LOGGED_IN, session.accessToken.length > 0);
  }

  static async save(context: common.UIAbilityContext, session: AuthSession): Promise<void> {
    SessionStore.context = context;
    SessionStore.applySession(session);
    await TokenStore.saveSession(context, session);
  }

  static async clear(): Promise<void> {
    if (SessionStore.context !== null) {
      try {
        await TokenStore.clearSession(SessionStore.context);
      } catch (error) {
        // The in-memory state must still be cleared.
      }
    }
    SessionStore.clearValues();
    SessionStore.context = null;
  }

  static currentSession(): AuthSession | null {
    const token: string = SessionStore.stringValue(StateKeys.AUTH_TOKEN);
    if (token.length === 0) {
      return null;
    }
    return new AuthSession(
      token,
      SessionStore.stringValue(StateKeys.AUTH_REFRESH_TOKEN),
      SessionStore.numberValue(StateKeys.AUTH_EXPIRES_AT),
      SessionStore.stringValue(StateKeys.AUTH_USERNAME),
      SessionStore.stringValue(StateKeys.AUTH_SERVER_URL)
    );
  }

  static token(): string {
    return SessionStore.stringValue(StateKeys.AUTH_TOKEN);
  }

  static serverUrl(): string {
    return SessionStore.stringValue(StateKeys.AUTH_SERVER_URL);
  }

  static accountKey(): string {
    return `${SessionStore.serverUrl()}|${SessionStore.stringValue(StateKeys.AUTH_USERNAME)}`;
  }

  static isLoggedIn(): boolean {
    return AppStorage.get<boolean>(StateKeys.AUTH_LOGGED_IN) === true;
  }

  private static clearValues(): void {
    AppStorage.setOrCreate(StateKeys.AUTH_TOKEN, '');
    AppStorage.setOrCreate(StateKeys.AUTH_REFRESH_TOKEN, '');
    AppStorage.setOrCreate(StateKeys.AUTH_EXPIRES_AT, 0);
    AppStorage.setOrCreate(StateKeys.AUTH_USERNAME, '');
    AppStorage.setOrCreate(StateKeys.AUTH_SERVER_URL, '');
    AppStorage.setOrCreate(StateKeys.AUTH_LOGGED_IN, false);
    AppStorage.setOrCreate(StateKeys.SELECTED_NOTE_ID, '');
    AppStorage.setOrCreate(StateKeys.SELECTED_NOTE_TITLE, '');
    AppStorage.setOrCreate(StateKeys.OPEN_GLOBAL_SEARCH, false);
    ReadingPositionStore.clear();
  }

  private static stringValue(key: string): string {
    const value: string | undefined = AppStorage.get<string>(key);
    return value ?? '';
  }

  private static numberValue(key: string): number {
    const value: number | undefined = AppStorage.get<number>(key);
    return value ?? 0;
  }
}
