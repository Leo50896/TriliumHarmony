export class AppConstants {
  static readonly APP_VERSION: string = 'v1.0.0';
  static readonly APP_NAME: string = 'Trilium 笔记';
  static readonly PREF_STORE_NAME: string = 'trilium_auth';
  static readonly PREF_THEME_STORE_NAME: string = 'trilium_theme';
  static readonly KEY_THEME_MODE: string = 'theme_mode';
  static readonly KEY_ACCESS_TOKEN: string = 'access_token';
  static readonly KEY_REFRESH_TOKEN: string = 'refresh_token';
  static readonly KEY_EXPIRES_AT: string = 'expires_at';
  static readonly KEY_USERNAME: string = 'username';
  static readonly KEY_SERVER_URL: string = 'server_url';
  static readonly TOKEN_EXPIRY_SKEW_MS: number = 30 * 1000;
}
