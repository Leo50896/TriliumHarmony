import { common } from '@kit.AbilityKit';
import { AuthResult, AuthSession, LoginPayload } from '../models/AuthModels';
import { AuthService } from '../services/AuthService';
import { SessionStore } from '../services/SessionStore';
import { MockConfig } from '../constants/MockConfig';
import { AppConstants } from '../constants/AppConstants';
import { AppIcon } from '../components/AppIcon';
import { AuthTextField } from '../components/AuthTextField';
import { LogoMark } from '../components/LogoMark';
import { OtpInput } from '../components/OtpInput';

/**
 * Login owns the two-step authentication state machine:
 *   loginStep 1 -> credentials
 *   loginStep 2 -> six-digit TOTP challenge
 * Navigation is deliberately local because the parent page only needs to know
 * whether authentication succeeded, not which step is showing.
 */
@Component
export struct LoginView {
  onAuthenticated: () => void = () => {};
  @Prop initialStep: number = 1;

  @State private loginStep: number = 1;
  @State private username: string = '';
  @State private password: string = '';
  @State private serverUrl: string = MockConfig.DEFAULT_SERVER_URL;
  @State private activeServer: string = MockConfig.DEFAULT_SERVER_URL;
  @State private challengeId: string = '';
  @State private otpCode: string = '';
  @State private isLoading: boolean = false;
  @State private isVerifying: boolean = false;
  @State private isResending: boolean = false;
  @State private errorMessage: string = '';
  @State private infoMessage: string = '';
  @State private countdown: number = 0;
  private timerId: number = -1;

  aboutToAppear(): void {
    // Preview-only entry point. Production always starts at the credentials
    // step (initialStep defaults to 1).
    if (this.initialStep === 2) {
      this.username = 'trilium';
      this.activeServer = MockConfig.DEFAULT_SERVER_URL;
      this.challengeId = 'preview-challenge';
      this.loginStep = 2;
      if (AuthService.useMock) {
        this.startCountdown();
      }
      this.focusOtpInput();
    }
  }

  aboutToDisappear(): void {
    this.stopCountdown();
  }

  private stopCountdown(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private startCountdown(): void {
    this.stopCountdown();
    this.countdown = MockConfig.OTP_RESEND_SECONDS;
    this.timerId = setInterval(() => {
      if (this.countdown <= 1) {
        this.countdown = 0;
        this.stopCountdown();
      } else {
        this.countdown -= 1;
      }
    }, 1000);
  }

  private focusOtpInput(): void {
    setTimeout(() => {
      try {
        this.getUIContext().getFocusController().requestFocus('trilium-otp-input');
      } catch (error) {
        // The user can still tap the OTP cells to focus the hidden input.
      }
    }, 260);
  }

  private dismissKeyboard(): void {
    try {
      this.getUIContext().getFocusController().clearFocus();
    } catch (error) {
      // Focus can already be gone, for example after a page transition.
    }
  }

  private async completeLogin(session: AuthSession): Promise<void> {
    // Persisting the session is best-effort so the Previewer (which does not
    // provide a full ability context) can still walk through the whole flow.
    // On a device this succeeds and the next cold start skips the login page.
    try {
      const hostContext: common.Context | undefined = this.getUIContext().getHostContext();
      if (hostContext === undefined) {
        SessionStore.applySession(session);
      } else {
        await SessionStore.save(hostContext as common.UIAbilityContext, session);
      }
    } catch (error) {
      // The in-memory session remains valid for the current app session.
      SessionStore.applySession(session);
    }
    this.onAuthenticated();
  }

  private async handleLogin(): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.errorMessage = '';
    this.infoMessage = '';

    const trimmedUser: string = this.username.trim();
    const effectiveServer: string = this.serverUrl.trim().length > 0
      ? this.serverUrl.trim() : MockConfig.DEFAULT_SERVER_URL;
    if (trimmedUser.length === 0) {
      this.dismissKeyboard();
      this.errorMessage = '请输入用户名';
      return;
    }
    if (this.password.length < 6) {
      this.dismissKeyboard();
      this.errorMessage = '密码至少需要 6 位';
      return;
    }
    if (!effectiveServer.startsWith('http://') && !effectiveServer.startsWith('https://')) {
      this.dismissKeyboard();
      this.errorMessage = '服务器地址需以 http:// 或 https:// 开头';
      return;
    }

    this.isLoading = true;
    try {
      if (!AuthService.useMock) {
        const requiresTotp: boolean | null = await AuthService.requiresTotp(effectiveServer);
        if (requiresTotp === true) {
          // The password is kept in memory only; it is submitted together with
          // the TOTP token in the next step, matching Trilium's login/token API.
          AuthService.setActiveIdentity(trimmedUser, effectiveServer);
          this.activeServer = AuthService.normalizeBaseUrl(effectiveServer);
          this.challengeId = '';
          this.otpCode = '';
          this.loginStep = 2;
          this.countdown = 0;
          this.focusOtpInput();
          return;
        }
      }

      const result: AuthResult = await AuthService.login(
        new LoginPayload(trimmedUser, this.password, effectiveServer)
      );
      if (!result.success) {
        this.dismissKeyboard();
        this.errorMessage = result.message;
        return;
      }
      if (result.requiresTwoFactor) {
        this.challengeId = result.challengeId;
        this.activeServer = AuthService.normalizeBaseUrl(effectiveServer);
        this.otpCode = '';
        this.loginStep = 2;
        if (AuthService.useMock) {
          this.startCountdown();
        } else {
          this.countdown = 0;
        }
        this.focusOtpInput();
        return;
      }
      if (result.session !== null) {
        await this.completeLogin(result.session);
      }
    } finally {
      this.isLoading = false;
    }
  }

  private async verifyOtp(): Promise<void> {
    if (this.isVerifying || this.otpCode.length !== 6) {
      return;
    }
    this.errorMessage = '';
    this.infoMessage = '';
    this.isVerifying = true;
    try {
      const result: AuthResult = await AuthService.verifyTwoFactor(
        this.activeServer,
        this.challengeId,
        this.otpCode,
        this.password
      );
      if (!result.success) {
        this.dismissKeyboard();
        this.errorMessage = result.message;
        this.otpCode = '';
        return;
      }
      if (result.session !== null) {
        await this.completeLogin(result.session);
      }
    } finally {
      this.isVerifying = false;
    }
  }

  private async resendCode(): Promise<void> {
    if (!AuthService.useMock || this.countdown > 0 || this.isResending) {
      return;
    }
    this.errorMessage = '';
    this.infoMessage = '';
    this.isResending = true;
    try {
      const result: AuthResult = await AuthService.resendTwoFactor(this.activeServer, this.challengeId);
      if (result.success) {
        this.infoMessage = result.message;
        this.otpCode = '';
        this.startCountdown();
      } else {
        this.errorMessage = result.message;
      }
    } finally {
      this.isResending = false;
    }
  }

  private backToCredentials(): void {
    if (this.isVerifying || this.isLoading) {
      return;
    }
    this.stopCountdown();
    this.loginStep = 1;
    this.challengeId = '';
    this.otpCode = '';
    this.errorMessage = '';
    this.infoMessage = '';
    this.countdown = 0;
  }

  @Builder
  private ErrorBanner() {
    Row({ space: 8 }) {
      Text('!')
        .width(18)
        .height(18)
        .textAlign(TextAlign.Center)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.danger'))
        .backgroundColor($r('app.color.danger_bg'))
        .borderRadius(9)
      Text(this.errorMessage)
        .layoutWeight(1)
        .fontSize(13)
        .lineHeight(19)
        .fontColor($r('app.color.danger'))
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.danger_bg'))
    .borderRadius(12)
  }

  @Builder
  private InfoBanner() {
    Row({ space: 8 }) {
      Row()
        .width(7)
        .height(7)
        .borderRadius(4)
        .backgroundColor($r('app.color.primary'))
      Text(this.infoMessage)
        .layoutWeight(1)
        .fontSize(13)
        .lineHeight(19)
        .fontColor($r('app.color.primary_text'))
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.primary_soft'))
    .borderRadius(12)
  }

  @Builder
  private PrimaryAction(label: string, busyLabel: string, busy: boolean, action: () => void) {
    Button({ type: ButtonType.Capsule, stateEffect: true }) {
      Row({ space: 9 }) {
        if (busy) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color($r('app.color.text_on_primary'))
        }
        Text(busy ? busyLabel : label)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_on_primary'))
          .letterSpacing(1)
      }
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height(52)
    .borderRadius(26)
    .backgroundColor($r('app.color.primary'))
    .opacity(busy ? 0.82 : 1)
    .enabled(!busy)
    .onClick(action)
  }

  @Builder
  private CredentialsStep() {
    Column() {
      LogoMark({ markSize: 76, showGlow: false })
      Text(AppConstants.APP_NAME)
        .fontSize(33)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .letterSpacing(0.3)
        .margin({ top: 0 })
      Text('安全连接 · 随处书写')
        .fontSize(13)
        .fontColor($r('app.color.text_tertiary'))
        .letterSpacing(0.4)
        .margin({ top: 8 })

      Column({ space: 12 }) {
        AuthTextField({
          value: $username,
          placeholder: '用户名',
          icon: $r('app.media.ic_user'),
          onSubmitted: () => {
            this.handleLogin();
          }
        })
        AuthTextField({
          value: $password,
          placeholder: '密码',
          icon: $r('app.media.ic_lock'),
          isPassword: true,
          onSubmitted: () => {
            this.handleLogin();
          }
        })
        AuthTextField({
          value: $serverUrl,
          placeholder: MockConfig.DEFAULT_SERVER_URL,
          icon: $r('app.media.ic_server'),
          inputType: InputType.Normal,
          onSubmitted: () => {
            this.handleLogin();
          }
        })
      }
      .width('100%')
      .margin({ top: 44 })

      if (this.errorMessage.length > 0) {
        Column() {
          this.ErrorBanner()
        }
        .width('100%')
        .margin({ top: 14 })
      }

      Column() {
        this.PrimaryAction('登录', '正在登录', this.isLoading, () => {
          this.handleLogin();
        })
      }
      .width('100%')
      .margin({ top: 22 })

      if (MockConfig.USE_MOCK) {
        Row({ space: 7 }) {
          Row()
            .width(5)
            .height(5)
            .borderRadius(3)
            .backgroundColor($r('app.color.warning'))
          Text('Mock 模式：任意账号 + 6 位密码，动态码 123456')
            .fontSize(11.5)
            .fontColor($r('app.color.text_tertiary'))
            .layoutWeight(1)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 18 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private TwoFactorStep() {
    Column() {
      Row({ space: 2 }) {
        AppIcon({
          icon: $r('app.media.ic_back'),
          iconSize: 21,
          tint: $r('app.color.text_secondary')
        })
        Text('返回')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .height(36)
      .onClick(() => {
        this.backToCredentials();
      })
      .alignSelf(ItemAlign.Start)

      Stack({ alignContent: Alignment.Center }) {
        Row()
          .width(76)
          .height(76)
          .borderRadius(38)
          .backgroundColor($r('app.color.primary_soft'))
        Row()
          .width(76)
          .height(76)
          .borderRadius(38)
          .backgroundColor($r('app.color.primary'))
          .opacity(0.12)
          .blur(18)
        AppIcon({
          icon: $r('app.media.ic_lock'),
          iconSize: 30,
          tint: $r('app.color.primary_text')
        })
      }
      .margin({ top: 24 })

      Text('两步验证')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 18 })
      Text('请输入身份验证器中显示的 6 位动态验证码')
        .fontSize(14)
        .lineHeight(22)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .margin({ top: 8, left: 16, right: 16 })

      Row({ space: 7 }) {
        AppIcon({
          icon: $r('app.media.ic_user'),
          iconSize: 14,
          tint: $r('app.color.primary_text')
        })
        Text(`${this.username.trim()} · ${this.activeServer.replace('https://', '').replace('http://', '')}`)
          .fontSize(12)
          .fontColor($r('app.color.primary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .constraintSize({ maxWidth: '100%' })
      .padding({ left: 13, right: 13, top: 7, bottom: 7 })
      .backgroundColor($r('app.color.primary_soft'))
      .borderRadius(16)
      .margin({ top: 16 })

      OtpInput({
        code: $otpCode,
        onComplete: () => {
          this.verifyOtp();
        }
      })
        .margin({ top: 30 })

      if (this.errorMessage.length > 0) {
        Column() {
          this.ErrorBanner()
        }
        .width('100%')
        .margin({ top: 14 })
      }

      if (this.infoMessage.length > 0) {
        Column() {
          this.InfoBanner()
        }
        .width('100%')
        .margin({ top: 14 })
      }

      Column() {
        this.PrimaryAction('验证并登录', '正在验证', this.isVerifying, () => {
          this.verifyOtp();
        })
      }
      .width('100%')
      .margin({ top: 24 })

      if (AuthService.useMock) {
        Row({ space: 6 }) {
          if (this.isResending) {
            LoadingProgress()
              .width(14)
              .height(14)
              .color($r('app.color.primary'))
          }
          if (this.countdown > 0) {
            Text(`${this.countdown} 秒后可重新发送`)
              .fontSize(13)
              .fontColor($r('app.color.text_tertiary'))
          } else {
            Text('重新发送验证码')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.primary_text'))
              .onClick(() => {
                this.resendCode();
              })
          }
        }
        .margin({ top: 18 })
      } else {
        Row({ space: 7 }) {
          AppIcon({
            icon: $r('app.media.ic_clock'),
            iconSize: 14,
            tint: $r('app.color.text_tertiary')
          })
          Text('动态验证码由身份验证器生成，每 30 秒更新')
            .fontSize(12.5)
            .fontColor($r('app.color.text_tertiary'))
        }
        .margin({ top: 18 })
      }

      Row({ space: 4 }) {
        AppIcon({
          icon: $r('app.media.ic_back'),
          iconSize: 13,
          tint: $r('app.color.text_secondary')
        })
        Text('返回上一步')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      .margin({ top: 26 })
      .onClick(() => {
        this.backToCredentials();
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 4 })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Scroll() {
          Column() {
            if (this.loginStep === 1) {
              this.CredentialsStep()
            } else {
              this.TwoFactorStep()
            }
          }
          .width('100%')
          .constraintSize({ maxWidth: 440 })
          .padding({ left: 28, right: 28, top: 54, bottom: 28 })
          .alignItems(HorizontalAlign.Center)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
        .align(Alignment.Top)

        Text(`${AppConstants.APP_NAME} ${AppConstants.APP_VERSION}`)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .opacity(0.75)
          .letterSpacing(0.8)
          .margin({ bottom: 18 })
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }
}
