import { common } from '@kit.AbilityKit';
import { AppConstants } from '../constants/AppConstants';
import { LogoMark } from '../components/LogoMark';
import { LoginView } from '../views/LoginView';
import { MainView } from '../views/MainView';
import { AuthSession } from '../models/AuthModels';
import { SessionStore } from '../services/SessionStore';
import { SettingsStore } from '../services/SettingsStore';
import { BiometricService } from '../services/BiometricService';
import { StateKeys } from '../constants/StateKeys';
import { font } from '@kit.ArkUI';

/**
 * App entry and session gate.
 *
 * phase 0: restoring a persisted session
 * phase 1: login / 2FA
 * phase 2: notes app
 *
 * The Root page is also the Previewer entry. In Preview, persistence can be
 * unavailable; the splash falls back to login and the mock flow still reaches
 * the main screen.
 */
@Entry
@Component
struct Index {
  @State private phase: number = 0;
  @StorageLink('auth.loggedIn') @Watch('onLoggedInChanged') private loggedIn: boolean = false;
  @StorageLink(StateKeys.SYNC_INTERVAL) @Watch('onSyncIntervalChanged')
  private syncInterval: number = 30;
  @StorageLink(StateKeys.BIOMETRIC_UNLOCK) private faceUnlock: boolean = false;
  @State private locked: boolean = false;
  @State private unlocking: boolean = false;
  @State private lockMessage: string = '';
  @StorageLink('app.foregroundTick') @Watch('onAppForeground') private foregroundTick: number = 0;
  @StorageLink('app.backgroundTick') @Watch('onAppBackground') private backgroundTick: number = 0;
  private heartbeatTimer: number = -1;

  private onAppBackground(): void {
    if (this.phase === 2 && this.faceUnlock && !this.unlocking) {
      this.locked = true;
    }
  }

  private onAppForeground(): void {
    if (this.phase === 2 && this.faceUnlock && !this.unlocking) {
      this.locked = true;
      setTimeout(() => {
        this.attemptFaceUnlock();
      }, 180);
    }
  }

  aboutToAppear(): void {
    try {
      font.registerFont({ familyName: 'boxicons', familySrc: $rawfile('boxicons.ttf') });
    } catch (error) {
      console.error(`BOXICONS_REGISTER_FAILED ${JSON.stringify(error)}`);
    }
    SessionStore.installDefaults();
    AppStorage.setOrCreate(StateKeys.BACK_AVAILABLE, false);
    this.initializeApp();
  }

  onBackPress(): boolean {
    if (this.phase !== 2 || this.locked) {
      return false;
    }
    if (AppStorage.get<boolean>(StateKeys.BACK_AVAILABLE) !== true) {
      return false;
    }
    const request: number = AppStorage.get<number>(StateKeys.BACK_REQUEST) ?? 0;
    AppStorage.setOrCreate(StateKeys.BACK_REQUEST, request + 1);
    return true;
  }

  private async initializeApp(): Promise<void> {
    const hostContext: common.Context | undefined = this.getUIContext().getHostContext();
    if (hostContext !== undefined) {
      await SettingsStore.initialize(hostContext as common.UIAbilityContext);
    }
    await this.restoreSession();
    if (this.phase === 2 && this.faceUnlock) {
      this.locked = true;
      setTimeout(() => {
        this.attemptFaceUnlock();
      }, 250);
    }
  }

  private async attemptFaceUnlock(): Promise<void> {
    if (this.unlocking) return;
    this.unlocking = true;
    this.lockMessage = '';
    const ok: boolean = await BiometricService.authenticate('解锁 Trilium 笔记');
    this.unlocking = false;
    if (ok) {
      this.locked = false;
    } else {
      this.lockMessage = '人脸验证未通过，请重试';
    }
  }

  aboutToDisappear(): void {
    this.stopHeartbeat();
  }

  onPageShow(): void {
    this.startHeartbeat();
    setTimeout(() => {
      if (this.loggedIn) {
        AppStorage.setOrCreate('sync.force', true);
      }
    }, 500);
  }

  onPageHide(): void {
    this.stopHeartbeat();
  }

  private startHeartbeat(): void {
    this.stopHeartbeat();
    this.scheduleHeartbeat();
  }

  private scheduleHeartbeat(): void {
    if (this.syncInterval <= 0) {
      return;
    }
    this.heartbeatTimer = setTimeout(() => {
      console.info('HEARTBEAT_TICK');
      if (this.loggedIn && AppStorage.get<boolean>('editor.editing') !== true) {
        AppStorage.setOrCreate('sync.force', true);
      }
      this.scheduleHeartbeat();
    }, this.syncInterval * 1000);
  }

  private onSyncIntervalChanged(): void {
    this.startHeartbeat();
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimer >= 0) {
      clearTimeout(this.heartbeatTimer);
      this.heartbeatTimer = -1;
    }
  }

  private onLoggedInChanged(): void {
    if (!this.loggedIn && this.phase === 2) {
      this.phase = 1;
    }
  }

  private async restoreSession(): Promise<void> {
    try {
      const hostContext: common.Context | undefined = this.getUIContext().getHostContext();
      if (hostContext === undefined) {
        this.phase = 1;
        return;
      }
      const context: common.UIAbilityContext = hostContext as common.UIAbilityContext;
      const session: AuthSession | null = await SessionStore.initialize(context);
      this.phase = session !== null ? 2 : 1;
    } catch (error) {
      this.phase = 1;
    }
  }

  private async handleLogout(): Promise<void> {
    await SessionStore.clear();
    this.locked = false;
    this.phase = 1;
  }

  @Builder
  private Splash() {
    Column({ space: 18 }) {
      LogoMark({ markSize: 76, showGlow: false })
      Text(AppConstants.APP_NAME)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: -4 })
      LoadingProgress()
        .width(26)
        .height(26)
        .color($r('app.color.primary'))
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.bg_primary'))
  }

  @Builder
  private LockScreen() {
    Column({ space: 14 }) {
      LogoMark({ markSize: 64, showGlow: false })
      Text('Trilium 已锁定')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 4 })
      Text('验证人脸后继续查看本地笔记')
        .fontSize(12.5)
        .fontColor($r('app.color.text_secondary'))
      if (this.lockMessage.length > 0) {
        Text(this.lockMessage)
          .fontSize(12)
          .fontColor($r('app.color.danger'))
      }
      Button(this.unlocking ? '正在验证…' : '验证人脸')
        .width(220)
        .height(44)
        .fontSize(15)
        .backgroundColor($r('app.color.primary'))
        .fontColor($r('app.color.text_on_primary'))
        .borderRadius(22)
        .enabled(!this.unlocking)
        .onClick(() => {
          this.attemptFaceUnlock();
        })
      Text('退出登录')
        .fontSize(12.5)
        .fontColor($r('app.color.text_tertiary'))
        .padding(6)
        .onClick(() => {
          this.handleLogout();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.bg_primary'))
  }

  build() {
    Stack() {
      if (this.phase === 0) {
        this.Splash()
      } else if (this.phase === 1) {
        LoginView({
          onAuthenticated: () => {
            this.phase = 2;
            this.locked = false;
          }
        })
      } else if (this.locked) {
        this.LockScreen()
      } else {
        MainView({
          onLogout: () => {
            this.handleLogout();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }
}
