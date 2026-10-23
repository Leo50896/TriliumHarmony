/**
 * Auth domain models shared by the mock backend and the real HTTP client.
 * Keeping these as classes makes the response mapping explicit under ArkTS
 * strict mode and gives the UI a single, well-typed result object.
 */

export const AUTH_ERROR_INVALID_CREDENTIALS: string = 'AUTH_INVALID_CREDENTIALS';
export const AUTH_ERROR_OTP_INVALID: string = 'AUTH_OTP_INVALID';
export const AUTH_ERROR_OTP_EXPIRED: string = 'AUTH_OTP_EXPIRED';
export const AUTH_ERROR_NETWORK: string = 'AUTH_NETWORK_ERROR';
export const AUTH_ERROR_UNKNOWN: string = 'AUTH_UNKNOWN_ERROR';

export class AuthSession {
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
  username: string;
  serverUrl: string;

  constructor(accessToken: string, refreshToken: string, expiresAt: number, username: string,
    serverUrl: string) {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
    this.expiresAt = expiresAt;
    this.username = username;
    this.serverUrl = serverUrl;
  }
}

export class AuthResult {
  success: boolean = false;
  requiresTwoFactor: boolean = false;
  challengeId: string = '';
  expiresIn: number = 0;
  message: string = '';
  errorCode: string = '';
  session: AuthSession | null = null;

  static signedIn(session: AuthSession, message: string = '登录成功'): AuthResult {
    const result: AuthResult = new AuthResult();
    result.success = true;
    result.session = session;
    result.message = message;
    return result;
  }

  static twoFactorRequired(challengeId: string, expiresIn: number, message: string = '请输入动态验证码'): AuthResult {
    const result: AuthResult = new AuthResult();
    result.success = true;
    result.requiresTwoFactor = true;
    result.challengeId = challengeId;
    result.expiresIn = expiresIn;
    result.message = message;
    return result;
  }

  static failure(errorCode: string, message: string): AuthResult {
    const result: AuthResult = new AuthResult();
    result.success = false;
    result.errorCode = errorCode;
    result.message = message;
    return result;
  }
}

export class LoginPayload {
  username: string;
  password: string;
  serverUrl: string;

  constructor(username: string, password: string, serverUrl: string) {
    this.username = username;
    this.password = password;
    this.serverUrl = serverUrl;
  }
}

export class TriliumTokenRequest {
  password: string;
  totpToken: string;
  tokenName: string;

  constructor(password: string, totpToken: string, tokenName: string) {
    this.password = password;
    this.totpToken = totpToken;
    this.tokenName = tokenName;
  }
}

/**
 * Response of POST /api/login/token.
 *
 * The current server returns `{ token }`; older builds/OpenAPI describe
 * `{ authToken }`. Both are accepted so the client works across versions.
 * A failed second factor is returned as 401 with `{ success: false, factor }`
 * where factor is `"password"` or `"totp"`.
 */
export interface TriliumTokenPayload {
  token?: string;
  authToken?: string;
  success?: boolean;
  factor?: string;
  message?: string;
  error?: string;
}

export interface TriliumBootstrapLogin {
  totpEnabled?: boolean;
  ssoEnabled?: boolean;
}

/**
 * The public bootstrap payload contains the login capabilities, including
 * `login.totpEnabled`, before any credentials are submitted. That lets the
 * client switch to the TOTP screen without causing a failed password attempt
 * on older servers that still return a plain 401 for every missing factor.
 */
export interface TriliumBootstrapPayload {
  login?: TriliumBootstrapLogin;
  triliumVersion?: string;
}


