import http from '@ohos.net.http';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AuthResult,
  AuthSession,
  AUTH_ERROR_INVALID_CREDENTIALS,
  AUTH_ERROR_NETWORK,
  AUTH_ERROR_OTP_EXPIRED,
  AUTH_ERROR_OTP_INVALID,
  LoginPayload,
  TriliumBootstrapPayload,
  TriliumTokenPayload,
  TriliumTokenRequest
} from '../models/AuthModels';
import { MockConfig } from '../constants/MockConfig';

const DOMAIN: number = 0x0000;
const TAG: string = 'TriliumAuth';
const TOKEN_NAME: string = 'Trilium HarmonyOS';
const REAL_TOKEN_TTL_MS: number = 30 * 24 * 60 * 60 * 1000;
const AUTH_RATE_LIMITED: string = 'AUTH_RATE_LIMITED';

/**
 * Authentication service.
 *
 * Real mode uses Trilium's own `POST /api/login/token`, which accepts the
 * password and, when TOTP is enabled, the 6-digit `totpToken` in the same
 * request. Because some server versions return a plain 401 for every missing
 * factor, 2FA capability is read from the public `GET /bootstrap` endpoint
 * instead of probing `/api/login/token` with a password-only request.
 *
 * Newer servers may additionally return:
 *
 *   { "success": false, "factor": "password" | "totp" }
 *
 * on 401. That is used only to improve the error message.
 */
export class AuthService {
  static useMock: boolean = MockConfig.USE_MOCK;

  private static mockChallengeExpiresAt: number = 0;
  private static mockChallengeId: string = '';
  private static activeUsername: string = 'trilium';
  private static activeServerUrl: string = MockConfig.DEFAULT_SERVER_URL;

  static async login(payload: LoginPayload): Promise<AuthResult> {
    if (AuthService.useMock) {
      return AuthService.mockLogin(payload);
    }

    const baseUrl: string = AuthService.normalizeBaseUrl(payload.serverUrl);
    AuthService.activeUsername = payload.username;
    AuthService.activeServerUrl = baseUrl;
    return AuthService.requestToken(baseUrl, payload.password, '', payload.username);
  }

  /**
   * Reads the public /bootstrap endpoint to discover whether the server
   * requires a TOTP code. Returns null when the endpoint cannot be read.
   */
  static async requiresTotp(serverUrl: string): Promise<boolean | null> {
    const request: http.HttpRequest = http.createHttp();
    const baseUrl: string = AuthService.normalizeBaseUrl(serverUrl);
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: {
        'Accept': 'application/json'
      },
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 10000,
      readTimeout: 15000
    };

    try {
      const response: http.HttpResponse = await request.request(`${baseUrl}/bootstrap`, options);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        return null;
      }
      const responseText: string = typeof response.result === 'string'
        ? response.result : JSON.stringify(response.result);
      const payload: TriliumBootstrapPayload = JSON.parse(responseText) as TriliumBootstrapPayload;
      if (payload.login !== undefined && typeof payload.login.totpEnabled === 'boolean') {
        return payload.login.totpEnabled;
      }
      return null;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Unable to read /bootstrap: %{public}s', JSON.stringify(error));
      return null;
    } finally {
      request.destroy();
    }
  }

  static async verifyTwoFactor(baseUrlValue: string, challengeId: string, code: string,
    password: string): Promise<AuthResult> {
    if (AuthService.useMock) {
      return AuthService.mockVerify(challengeId, code);
    }

    const baseUrl: string = AuthService.normalizeBaseUrl(baseUrlValue);
    return AuthService.requestToken(baseUrl, password, code, AuthService.activeUsername);
  }

  /**
   * Keeps the display name used by the stored session when the password step
   * is completed without calling /api/login/token (the 2FA branch).
   */
  static setActiveIdentity(username: string, serverUrl: string): void {
    AuthService.activeUsername = username;
    AuthService.activeServerUrl = AuthService.normalizeBaseUrl(serverUrl);
  }

  static async resendTwoFactor(baseUrlValue: string, challengeId: string): Promise<AuthResult> {
    if (AuthService.useMock) {
      return AuthService.mockResend(challengeId);
    }

    return AuthResult.failure(
      'AUTH_TOTP_MANUAL',
      '动态验证码由身份验证器生成，请直接输入最新验证码'
    );
  }

  private static async requestToken(baseUrl: string, password: string, totpToken: string,
    username: string): Promise<AuthResult> {
    const request: http.HttpRequest = http.createHttp();
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: JSON.stringify(new TriliumTokenRequest(password, totpToken, TOKEN_NAME)),
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 10000,
      readTimeout: 15000
    };

    try {
      const response: http.HttpResponse = await request.request(`${baseUrl}/api/login/token`, options);
      const responseText: string = typeof response.result === 'string'
        ? response.result : JSON.stringify(response.result);
      const payload: TriliumTokenPayload = AuthService.parsePayload(responseText);
      const message: string = AuthService.pickString(
        payload.message,
        AuthService.pickString(payload.error, '')
      );

      if (response.responseCode >= 200 && response.responseCode < 300) {
        const token: string = AuthService.pickString(payload.token, payload.authToken);
        if (token.length === 0) {
          return AuthResult.failure('AUTH_TOKEN_MISSING', '服务器未返回 ETAPI Token');
        }
        const session: AuthSession = new AuthSession(
          token,
          '',
          Date.now() + REAL_TOKEN_TTL_MS,
          username,
          baseUrl
        );
        return AuthResult.signedIn(session, '登录成功');
      }

      if (response.responseCode === 401) {
        if (payload.factor === 'totp') {
          if (totpToken.length === 0) {
            return AuthResult.twoFactorRequired(
              '',
              MockConfig.MOCK_CHALLENGE_TTL_SECONDS,
              '该账户已开启双因子认证，请输入动态验证码'
            );
          }
          return AuthResult.failure(AUTH_ERROR_OTP_INVALID, '动态验证码错误或已过期，请重新输入');
        }
        if (payload.factor === 'password') {
          return AuthResult.failure(
            AUTH_ERROR_INVALID_CREDENTIALS,
            totpToken.length > 0 ? '密码错误，请返回上一步重新输入' : '密码错误，请检查后重试'
          );
        }
        return AuthResult.failure(
          AUTH_ERROR_INVALID_CREDENTIALS,
          message.length > 0 ? message
            : (totpToken.length > 0 ? '密码或动态验证码错误，请检查后重试' : '密码错误，请检查后重试')
        );
      }

      if (response.responseCode === 429) {
        return AuthResult.failure(AUTH_RATE_LIMITED, '登录尝试次数过多，请 15 分钟后再试');
      }

      return AuthResult.failure(
        `HTTP_${response.responseCode}`,
        message.length > 0 ? message : `服务器返回 ${response.responseCode}`
      );
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Auth request failed: %{public}s', JSON.stringify(error));
      return AuthResult.failure(AUTH_ERROR_NETWORK, '网络请求失败，请检查服务器地址与网络连接');
    } finally {
      request.destroy();
    }
  }

  private static parsePayload(text: string): TriliumTokenPayload {
    try {
      return JSON.parse(text) as TriliumTokenPayload;
    } catch (error) {
      return {};
    }
  }

  private static async mockLogin(payload: LoginPayload): Promise<AuthResult> {
    await AuthService.delay(MockConfig.NETWORK_DELAY_MS);

    const username: string = payload.username.trim();
    if (username.length < 2 || payload.password.length < 6) {
      return AuthResult.failure(AUTH_ERROR_INVALID_CREDENTIALS, '账号或密码错误，请检查后重试');
    }
    if (payload.password === 'wrong-password') {
      return AuthResult.failure(AUTH_ERROR_INVALID_CREDENTIALS, '账号或密码错误，请检查后重试');
    }
    if (username === 'network-error') {
      return AuthResult.failure(AUTH_ERROR_NETWORK, '无法连接服务器，请检查网络或服务器地址');
    }
    if (!payload.serverUrl.startsWith('http://') && !payload.serverUrl.startsWith('https://')) {
      return AuthResult.failure(AUTH_ERROR_NETWORK, '服务器地址需要以 http:// 或 https:// 开头');
    }

    AuthService.mockChallengeId = `mock-challenge-${Date.now()}`;
    AuthService.mockChallengeExpiresAt =
      Date.now() + MockConfig.MOCK_CHALLENGE_TTL_SECONDS * 1000;
    AuthService.activeUsername = username;
    AuthService.activeServerUrl = AuthService.normalizeBaseUrl(payload.serverUrl);

    return AuthResult.twoFactorRequired(
      AuthService.mockChallengeId,
      MockConfig.MOCK_CHALLENGE_TTL_SECONDS,
      '该账户已开启双因子认证，请输入动态验证码'
    );
  }

  private static async mockVerify(challengeId: string, code: string): Promise<AuthResult> {
    await AuthService.delay(MockConfig.NETWORK_DELAY_MS);
    if (challengeId.length === 0 || challengeId !== AuthService.mockChallengeId) {
      return AuthResult.failure(AUTH_ERROR_OTP_EXPIRED, '验证会话已过期，请返回上一步重新登录');
    }
    if (AuthService.mockChallengeExpiresAt < Date.now()) {
      return AuthResult.failure(AUTH_ERROR_OTP_EXPIRED, '验证码已过期，请重新获取');
    }
    if (code === MockConfig.MOCK_EXPIRED_OTP) {
      return AuthResult.failure(AUTH_ERROR_OTP_EXPIRED, '验证码已过期，请重新获取');
    }
    if (code !== MockConfig.MOCK_OTP) {
      return AuthResult.failure(AUTH_ERROR_OTP_INVALID, '验证码错误，请核对后重试');
    }

    const now: number = Date.now();
    const session: AuthSession = new AuthSession(
      `mock_access_${now}`,
      `mock_refresh_${now}`,
      now + 7 * 24 * 60 * 60 * 1000,
      AuthService.activeUsername,
      AuthService.activeServerUrl
    );
    return AuthResult.signedIn(session);
  }

  private static async mockResend(challengeId: string): Promise<AuthResult> {
    await AuthService.delay(500);
    if (challengeId.length === 0) {
      return AuthResult.failure(AUTH_ERROR_OTP_EXPIRED, '验证会话已过期，请返回上一步重新登录');
    }
    AuthService.mockChallengeExpiresAt =
      Date.now() + MockConfig.MOCK_CHALLENGE_TTL_SECONDS * 1000;
    return AuthResult.twoFactorRequired(challengeId, MockConfig.MOCK_CHALLENGE_TTL_SECONDS,
      '新的验证码已发送');
  }

  private static pickString(primary: string | undefined, secondary: string | undefined): string {
    if (primary !== undefined && primary.length > 0) {
      return primary;
    }
    if (secondary !== undefined && secondary.length > 0) {
      return secondary;
    }
    return '';
  }

  static normalizeBaseUrl(value: string): string {
    let result: string = value.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => resolve(), ms);
    });
  }
}
