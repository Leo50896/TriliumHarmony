/**
 * AppStorage keys. Keep these in one place so components and services cannot
 * drift apart on string literals.
 */
export class StateKeys {
  static readonly AUTH_TOKEN: string = 'auth.token';
  static readonly AUTH_REFRESH_TOKEN: string = 'auth.refreshToken';
  static readonly AUTH_EXPIRES_AT: string = 'auth.expiresAt';
  static readonly AUTH_USERNAME: string = 'auth.username';
  static readonly AUTH_SERVER_URL: string = 'auth.serverUrl';
  static readonly SYNC_FORCE: string = 'sync.force';
  static readonly EDITOR_EDITING: string = 'editor.editing';
  static readonly AUTH_LOGGED_IN: string = 'auth.loggedIn';
  static readonly THEME_MODE: string = 'app.themeMode';
  static readonly SYNC_INTERVAL: string = 'sync.intervalSeconds';
  static readonly READER_FONT_SIZE: string = 'reader.fontSize';
  static readonly BIOMETRIC_UNLOCK: string = 'security.faceUnlock';

  static readonly SELECTED_NOTE_ID: string = 'nav.selectedNoteId';
  static readonly SELECTED_NOTE_TITLE: string = 'nav.selectedNoteTitle';
  static readonly OPEN_GLOBAL_SEARCH: string = 'nav.openGlobalSearch';
  static readonly BACK_REQUEST: string = 'nav.backRequest';
  static readonly BACK_AVAILABLE: string = 'nav.backAvailable';
  static readonly EDITOR_CLOSE_SHEET: string = 'nav.editorCloseSheet';
  static readonly EDITOR_SHEET_OPEN: string = 'nav.editorSheetOpen';
  static readonly PDF_CURRENT_PAGE: string = 'pdf.currentPage';
  static readonly PDF_RETURN_FIRST: string = 'pdf.returnFirst';
}
