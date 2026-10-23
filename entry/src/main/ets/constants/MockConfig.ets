/**
 * Runtime configuration.
 *
 * The app now defaults to the real Trilium server and uses the server's
 * `POST /api/login/token` endpoint (password + optional TOTP). Set USE_MOCK to
 * true to run the offline demo flow without a server.
 */
export class MockConfig {
  static readonly USE_MOCK: boolean = false;
  static readonly MOCK_OTP: string = '123456';
  static readonly MOCK_EXPIRED_OTP: string = '000000';
  static readonly DEFAULT_SERVER_URL: string = 'https://notes.xinlin93.top';
  static readonly NETWORK_DELAY_MS: number = 900;
  static readonly OTP_RESEND_SECONDS: number = 60;
  static readonly MOCK_CHALLENGE_TTL_SECONDS: number = 300;
}
