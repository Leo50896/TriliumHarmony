import { common } from '@kit.AbilityKit';
import { AppConstants } from '../constants/AppConstants';
import { AppIcon } from '../components/AppIcon';
import { SettingsNavRow, SettingsSliderRow } from '../components/SettingsRows';
import { ImageDiskCache } from '../services/ImageDiskCache';
import { ThemeService } from '../services/ThemeService';
import { SessionStore } from '../services/SessionStore';
import { SettingsStore } from '../services/SettingsStore';
import { LocalStore } from '../services/LocalStore';
import { SyncService, SyncResult } from '../services/SyncService';
import { AuthSession } from '../models/AuthModels';
import { TriliumNote } from '../models/TriliumModels';
import { StateKeys } from '../constants/StateKeys';
import { BiometricService } from '../services/BiometricService';

/**
 * Settings surface backed by real session, local cache and sync state.
 * Account rows are read-only summaries; sync cadence and reading font are
 * persisted and consumed by Index/EditorView.
 */
@Component
export struct SettingsView {
  onBack: () => void = () => {};
  onLogout: () => void = () => {};
  onOpenLicense: () => void = () => {};

  @StorageLink(StateKeys.READER_FONT_SIZE) private fontSize: number = 16;
  @StorageLink(StateKeys.SYNC_INTERVAL) private syncInterval: number = 30;
  @StorageLink(StateKeys.THEME_MODE) private themeMode: string = ThemeService.SYSTEM;
  @StorageLink(StateKeys.BIOMETRIC_UNLOCK) private faceUnlock: boolean = false;

  @State private username: string = '';
  @State private serverUrl: string = '';
  @State private noteCount: number = 0;
  @State private lastSyncLabel: string = '尚未同步';
  @State private syncing: boolean = false;
  @State private syncMenuOpen: boolean = false;
  @State private accountSheetOpen: boolean = false;
  @State private accountNameDraft: string = '';

  aboutToAppear(): void {
    this.refreshAccount();
    this.refreshCacheMeta();
  }

  private async toggleFaceUnlock(enabled: boolean): Promise<void> {
    if (enabled) {
      const ok: boolean = await BiometricService.authenticate('开启人脸解锁');
      if (!ok) {
        this.faceUnlock = false;
        this.notify('人脸验证未通过，未开启');
        return;
      }
    }
    this.faceUnlock = enabled;
    const context: common.UIAbilityContext | null = this.context();
    if (context !== null) {
      await SettingsStore.setFaceUnlock(context, enabled);
    }
    this.notify(enabled ? '已开启人脸解锁' : '已关闭人脸解锁');
  }

  private context(): common.UIAbilityContext | null {
    const hostContext: common.Context | undefined = this.getUIContext().getHostContext();
    return hostContext === undefined ? null : hostContext as common.UIAbilityContext;
  }

  private refreshAccount(): void {
    const session: AuthSession | null = SessionStore.currentSession();
    this.username = session !== null ? session.username : '';
    this.serverUrl = session !== null ? session.serverUrl : '';
  }

  private async refreshCacheMeta(): Promise<void> {
    const context: common.UIAbilityContext | null = this.context();
    if (context === null) {
      return;
    }
    try {
      const notes: TriliumNote[] = await LocalStore.all(context, SessionStore.accountKey());
      this.noteCount = notes.length;
      const stamp: number = await LocalStore.lastSyncTime(context, SessionStore.accountKey());
      this.lastSyncLabel = stamp > 0 ? this.relativeTime(stamp) : '尚未同步';
    } catch (error) {
      // Settings still renders account information without cache metadata.
    }
  }

  private relativeTime(stamp: number): string {
    const delta: number = Date.now() - stamp;
    if (delta < 60 * 1000) {
      return '刚刚';
    }
    if (delta < 60 * 60 * 1000) {
      return `${Math.floor(delta / 60000)} 分钟前`;
    }
    if (delta < 24 * 60 * 60 * 1000) {
      return `${Math.floor(delta / 3600000)} 小时前`;
    }
    return new Date(stamp).toLocaleDateString();
  }

  private themeLabel(mode: string): string {
    if (mode === ThemeService.LIGHT) {
      return '明亮';
    }
    if (mode === ThemeService.DARK) {
      return '暗黑';
    }
    return '跟随系统';
  }

  private syncLabel(): string {
    if (this.syncInterval <= 0) {
      return '手动';
    }
    if (this.syncInterval < 60) {
      return `${this.syncInterval} 秒`;
    }
    return '1 分钟';
  }

  private applyTheme(mode: string): void {
    this.themeMode = mode;
    const context: common.UIAbilityContext | null = this.context();
    if (context !== null) {
      ThemeService.setMode(context, mode).catch(() => {});
    }
  }

  private async setSyncInterval(seconds: number): Promise<void> {
    this.syncMenuOpen = false;
    const context: common.UIAbilityContext | null = this.context();
    if (context !== null) {
      await SettingsStore.setSyncInterval(context, seconds);
    } else {
      this.syncInterval = seconds;
    }
    this.notify(`同步频率：${seconds < 60 ? seconds + ' 秒' : '1 分钟'}`);
  }

  private async applyFontSize(size: number): Promise<void> {
    this.fontSize = Math.round(size);
    const context: common.UIAbilityContext | null = this.context();
    if (context !== null) {
      await SettingsStore.setReaderFontSize(context, this.fontSize);
    }
  }

  private async syncNow(): Promise<void> {
    if (this.syncing) {
      return;
    }
    const context: common.UIAbilityContext | null = this.context();
    const session: AuthSession | null = SessionStore.currentSession();
    if (context === null || session === null) {
      this.notify('当前未登录，无法同步');
      return;
    }
    this.syncing = true;
    try {
      const result: SyncResult = await SyncService.sync(context, session, SessionStore.accountKey());
      this.notify(result.fullSync ? `已同步 ${result.pulled} 篇笔记` : '增量同步完成');
      await this.refreshCacheMeta();
    } catch (error) {
      this.notify('同步失败，请检查服务器连接');
    } finally {
      this.syncing = false;
    }
  }

  private notify(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1600 });
    } catch (error) {
      // The action still completes without a toast.
    }
  }

  private async clearImageCache(): Promise<void> {
    const context: common.UIAbilityContext | null = this.context();
    if (context === null) {
      this.notify('当前环境无法清理缓存');
      return;
    }
    try {
      await ImageDiskCache.clear(context);
      this.notify('图片缓存已清理');
    } catch (error) {
      this.notify('清理图片缓存失败');
    }
  }

  @Builder
  private SectionTitle(title: string) {
    Text(title)
      .fontSize(12)
      .fontColor($r('app.color.text_secondary'))
      .letterSpacing(0.2)
      .width('100%')
      .padding({ left: 4, top: 22, bottom: 9 })
  }

  @Builder
  private CardDivider() {
    Divider()
      .strokeWidth(1)
      .color($r('app.color.divider'))
      .margin({ left: 58, right: 12 })
  }

  private openAccountSheet(): void {
    this.accountNameDraft = this.username;
    this.accountSheetOpen = true;
  }

  private async saveAccountName(): Promise<void> {
    const context: common.UIAbilityContext | null = this.context();
    const session: AuthSession | null = SessionStore.currentSession();
    const name: string = this.accountNameDraft.trim();
    if (context !== null && session !== null && name.length > 0) {
      const updated: AuthSession = new AuthSession(session.accessToken, session.refreshToken,
        session.expiresAt, name, session.serverUrl);
      await SessionStore.save(context, updated);
      this.username = name;
      this.notify('登录账号已更新');
    }
    this.accountSheetOpen = false;
  }

  @Builder
  private AccountSheet() {
    Column({ space: 16 }) {
      Text('账户信息')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Text('登录账号')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      TextInput({ text: this.accountNameDraft, placeholder: '登录账号' })
        .height(42)
        .fontSize(14)
        .backgroundColor($r('app.color.bg_secondary'))
        .borderRadius(9)
        .onChange((value: string) => {
          this.accountNameDraft = value;
        })

      Text('服务器')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Text(this.serverUrl)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding(10)
        .backgroundColor($r('app.color.bg_secondary'))
        .borderRadius(9)

      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .fontSize(13)
          .backgroundColor($r('app.color.bg_secondary'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.accountSheetOpen = false;
          })
        Button('保存')
          .layoutWeight(1)
          .height(40)
          .fontSize(13)
          .backgroundColor($r('app.color.primary'))
          .fontColor($r('app.color.text_on_primary'))
          .onClick(() => {
            this.saveAccountName();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
  }

  @Builder
  private SyncOptions() {
    Row({ space: 6 }) {
      ForEach([5, 30, 60], (seconds: number) => {
        Text(seconds < 60 ? `${seconds}秒` : '1分')
          .fontSize(12)
          .fontColor(this.syncInterval === seconds ? $r('app.color.primary') : $r('app.color.text_secondary'))
          .layoutWeight(1)
          .height(34)
          .textAlign(TextAlign.Center)
          .backgroundColor(this.syncInterval === seconds ?
            $r('app.color.bg_selected_soft') : $r('app.color.bg_secondary'))
          .borderRadius(8)
          .border({
            width: 1,
            color: this.syncInterval === seconds ? $r('app.color.primary') : $r('app.color.border')
          })
          .onClick(() => {
            this.setSyncInterval(seconds);
          })
      }, (seconds: number) => `sync-${seconds}`)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 8, bottom: 10 })
  }

  build() {
    Column() {
      Row({ space: 2 }) {
        Stack({ alignContent: Alignment.Center }) {
          AppIcon({
            icon: $r('app.media.ic_back'),
            iconSize: 21,
            tint: $r('app.color.text_primary')
          })
        }
        .width(38)
        .height(38)
        .borderRadius(19)
        .onClick(this.onBack)
        Blank()
      }
      .width('100%')
      .height(52)
      .padding({ left: 8, right: 8 })

      Scroll() {
        Column() {
          Column() {
            Text('设置')
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
              .padding({ left: 4, top: 2, bottom: 4 })

            this.SectionTitle('账户与同步')

            Column() {
              SettingsNavRow({
                icon: $r('app.media.ic_server'),
                title: '服务器',
                value: this.serverUrl.length > 0 ? this.serverUrl : '未连接',
                showChevron: false,
                showStatusDot: this.serverUrl.length > 0,
                onTap: () => {
                  this.notify(this.serverUrl.length > 0 ? `已连接 ${this.serverUrl}` : '尚未连接服务器');
                }
              })
              this.CardDivider()
              SettingsNavRow({
                icon: $r('app.media.ic_clock'),
                title: '同步频率',
                value: this.syncLabel(),
                showChevron: true,
                onTap: () => {
                  this.syncMenuOpen = !this.syncMenuOpen;
                }
              })
              if (this.syncMenuOpen) {
                this.SyncOptions()
              }
              this.CardDivider()
              SettingsNavRow({
                icon: $r('app.media.ic_sync'),
                title: this.syncing ? '正在同步…' : '立即同步',
                value: this.lastSyncLabel,
                showChevron: false,
                onTap: () => {
                  this.syncNow();
                }
              })
            }
            .width('100%')
            .backgroundColor($r('app.color.bg_surface'))
            .borderRadius(16)
            .border({ width: 1, color: $r('app.color.border') })
            .clip(true)

            this.SectionTitle('外观与阅读')

            Column() {
              SettingsNavRow({
                icon: $r('app.media.ic_theme'),
                title: '主题',
                value: this.themeLabel(this.themeMode),
                showChevron: false,
                onTap: () => {
                  this.notify(`当前主题：${this.themeLabel(this.themeMode)}`);
                }
              })
              this.CardDivider()
              this.ThemeSelector()
              this.CardDivider()
              SettingsSliderRow({
                title: `阅读字体 ${this.fontSize}`,
                value: $fontSize,
                onChanged: (value: number) => {
                  this.applyFontSize(value);
                }
              })
            }
            .width('100%')
            .backgroundColor($r('app.color.bg_surface'))
            .borderRadius(16)
            .border({ width: 1, color: $r('app.color.border') })
            .clip(true)

            this.SectionTitle('数据与安全')

            Column() {
              Row({ space: 12 }) {
                AppIcon({
                  icon: $r('app.media.ic_lock'),
                  iconSize: 18,
                  tint: $r('app.color.text_secondary')
                })
                Column({ space: 2 }) {
                  Text('人脸解锁')
                    .fontSize(14.5)
                    .fontColor($r('app.color.text_primary'))
                  Text('启动应用时验证人脸')
                    .fontSize(10.5)
                    .fontColor($r('app.color.text_tertiary'))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.faceUnlock })
                  .selectedColor($r('app.color.primary'))
                  .onChange((enabled: boolean) => {
                    this.toggleFaceUnlock(enabled);
                  })
              }
              .width('100%')
              .height(62)
              .padding({ left: 14, right: 14 })

              this.CardDivider()
              SettingsNavRow({
                icon: $r('app.media.ic_doc'),
                title: '本地笔记',
                value: `${this.noteCount} 篇`,
                showChevron: false,
                onTap: () => {
                  this.notify(`本地缓存 ${this.noteCount} 篇笔记`);
                }
              })
              this.CardDivider()
              SettingsNavRow({
                icon: $r('app.media.ic_sync'),
                title: '清理图片缓存',
                value: 'LRU 80 张',
                showChevron: true,
                onTap: () => {
                  this.clearImageCache();
                }
              })
            }
            .width('100%')
            .backgroundColor($r('app.color.bg_surface'))
            .borderRadius(16)
            .border({ width: 1, color: $r('app.color.border') })
            .clip(true)

            Row({ space: 10 }) {
              AppIcon({
                icon: $r('app.media.ic_doc'),
                iconSize: 17,
                tint: $r('app.color.text_secondary')
              })
              Text('开源许可与源码')
                .fontSize(14.5)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Text('AGPL-3.0')
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
              AppIcon({
                icon: $r('app.media.ic_chevron_right'),
                iconSize: 14,
                tint: $r('app.color.text_tertiary')
              })
            }
            .width('100%')
            .height(52)
            .padding({ left: 14, right: 14 })
            .backgroundColor($r('app.color.bg_surface'))
            .borderRadius(16)
            .border({ width: 1, color: $r('app.color.border') })
            .margin({ top: 22 })
            .onClick(this.onOpenLicense)

            Row({ space: 10 }) {
              AppIcon({
                icon: $r('app.media.ic_lock'),
                iconSize: 17,
                tint: $r('app.color.danger')
              })
              Text('退出登录')
                .fontSize(14.5)
                .fontColor($r('app.color.danger'))
              Blank()
            }
            .width('100%')
            .height(52)
            .padding({ left: 14, right: 14 })
            .backgroundColor($r('app.color.bg_surface'))
            .borderRadius(16)
            .border({ width: 1, color: $r('app.color.border') })
            .margin({ top: 12 })
            .onClick(this.onLogout)

            Text(`${AppConstants.APP_NAME} ${AppConstants.APP_VERSION}`)
              .fontSize(10.5)
              .fontColor($r('app.color.text_tertiary'))
              .opacity(0.55)
              .letterSpacing(0.7)
              .margin({ top: 42, bottom: 24 })
          }
          .width('100%')
          .constraintSize({ maxWidth: 560 })
          .padding({ left: 18, right: 18 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
    .bindSheet(this.accountSheetOpen, this.AccountSheet, {
      height: 360,
      dragBar: true,
      showClose: false,
      backgroundColor: $r('app.color.bg_primary'),
      onDisappear: () => {
        this.accountSheetOpen = false;
      }
    })
  }

  @Builder
  private ThemeSelector() {
    Row({ space: 6 }) {
      ForEach([ThemeService.SYSTEM, ThemeService.LIGHT, ThemeService.DARK],
        (mode: string) => {
          Text(this.themeLabel(mode))
            .fontSize(12.5)
            .fontWeight(this.themeMode === mode ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.themeMode === mode ? $r('app.color.primary') : $r('app.color.text_secondary'))
            .layoutWeight(1)
            .height(36)
            .textAlign(TextAlign.Center)
            .backgroundColor(this.themeMode === mode ?
              $r('app.color.bg_selected_soft') : $r('app.color.bg_secondary'))
            .borderRadius(9)
            .border({
              width: 1,
              color: this.themeMode === mode ? $r('app.color.primary') : $r('app.color.border')
            })
            .onClick(() => {
              this.applyTheme(mode);
            })
        }, (mode: string) => `theme-${mode}`)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
  }
}
