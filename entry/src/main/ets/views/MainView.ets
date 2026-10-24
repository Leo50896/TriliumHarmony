import { SideDrawer } from '../components/SideDrawer';
import { StateKeys } from '../constants/StateKeys';
import { EditorView } from './EditorView';
import { SettingsView } from './SettingsView';
import { NoteMapView } from './NoteMapView';
import { LicenseView } from './LicenseView';

/**
 * Post-login shell. SideBarContainer owns the drawer gesture, width and
 * overlay semantics; the content stack adds a scrim so the editorial layout
 * behind the drawer recedes just like the reference mockup.
 */
@Component
export struct MainView {
  onLogout: () => void = () => {};

  // The post-login landing screen is the synced note tree; closing it reveals
  // the reader/editor. This matches the "hamburger -> drawer" flow requested
  // for the first post-login screen.
  @State @Watch('onDrawerVisibilityChanged') private showDrawer: boolean = true;
  @State private currentView: string = 'editor';
  @StorageProp(StateKeys.SELECTED_NOTE_ID) @Watch('onSelectedNoteChanged')
  private selectedNoteId: string = '';
  @StorageLink(StateKeys.BACK_REQUEST) @Watch('onSystemBackRequest')
  private backRequest: number = 0;
  private viewHistory: string[] = [];
  private noteHistory: string[] = [];
  private lastNoteId: string = '';
  private suppressNoteHistory: boolean = false;

  aboutToAppear(): void {
    this.lastNoteId = this.selectedNoteId;
    this.updateBackAvailable();
  }

  private updateBackAvailable(): void {
    const canHandle: boolean = this.showDrawer || this.viewHistory.length > 0 || this.noteHistory.length > 0;
    AppStorage.setOrCreate(StateKeys.BACK_AVAILABLE, canHandle);
  }

  private onSelectedNoteChanged(): void {
    if (this.suppressNoteHistory) {
      this.lastNoteId = this.selectedNoteId;
      return;
    }
    if (this.currentView !== 'editor') {
      this.viewHistory = [];
      this.currentView = 'editor';
    }
    if (this.lastNoteId.length > 0 && this.lastNoteId !== this.selectedNoteId) {
      this.noteHistory.push(this.lastNoteId);
    }
    this.lastNoteId = this.selectedNoteId;
    this.updateBackAvailable();
  }

  private openView(view: string): void {
    if (view === this.currentView) {
      this.updateBackAvailable();
      return;
    }
    this.viewHistory.push(this.currentView);
    this.currentView = view;
    this.updateBackAvailable();
  }

  private openEditorRoot(): void {
    this.viewHistory = [];
    this.currentView = 'editor';
    this.updateBackAvailable();
  }

  private goBack(): boolean {
    if (this.showDrawer) {
      this.closeDrawer();
      return true;
    }
    if (this.viewHistory.length > 0) {
      const previous: string = this.viewHistory.pop() as string;
      this.currentView = previous;
      this.updateBackAvailable();
      return true;
    }
    if (this.noteHistory.length > 0) {
      const previousNote: string = this.noteHistory.pop() as string;
      this.suppressNoteHistory = true;
      AppStorage.setOrCreate(StateKeys.SELECTED_NOTE_ID, previousNote);
      AppStorage.setOrCreate(StateKeys.SELECTED_NOTE_TITLE, '');
      this.lastNoteId = previousNote;
      this.suppressNoteHistory = false;
      this.currentView = 'editor';
      this.updateBackAvailable();
      return true;
    }
    return false;
  }

  private onSystemBackRequest(): void {
    this.goBack();
  }

  private onDrawerVisibilityChanged(): void {
    const tick: number = AppStorage.get<number>('TEXT_SELECTION_DISMISS') ?? 0;
    AppStorage.setOrCreate('TEXT_SELECTION_DISMISS', tick + 1);
    this.updateBackAvailable();
    try {
      this.getUIContext().getFocusController().clearFocus();
    } catch (error) {
      // The drawer can still open without an active focus owner.
    }
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1400 });
    } catch (error) {
      // Drawer navigation is unaffected if the toast service is unavailable.
    }
  }

  private closeDrawer(): void {
    this.showDrawer = false;
    const tick: number = AppStorage.get<number>('TEXT_SELECTION_DISMISS') ?? 0;
    AppStorage.setOrCreate('TEXT_SELECTION_DISMISS', tick + 1);
    this.updateBackAvailable();
    try {
      this.getUIContext().getFocusController().clearFocus();
    } catch (error) {
      // No focused input to clear.
    }
  }

  build() {
    Stack() {
      SideBarContainer(SideBarContainerType.Overlay) {
      SideDrawer({
        visible: this.showDrawer,
        onCloseDrawer: () => {
          this.closeDrawer();
        },
        onOpenGlobalSearch: () => {
          this.openEditorRoot();
          this.closeDrawer();
          AppStorage.setOrCreate(StateKeys.OPEN_GLOBAL_SEARCH, true);
        },
        onOpenNote: (noteId: string, title: string) => {
          this.openEditorRoot();
          this.closeDrawer();
        },
        onOpenSettings: () => {
          this.closeDrawer();
          this.openView('settings');
        },
        onOpenNoteMap: () => {
          this.closeDrawer();
          this.openView('notemap');
        },
        onNewNote: () => {
          this.closeDrawer();
          this.openEditorRoot();
          this.toast('已新建笔记（界面演示）');
        },
        onSessionExpired: () => {
          this.onLogout();
        }
      })

      Stack({ alignContent: Alignment.TopStart }) {
        if (this.currentView === 'settings') {
          SettingsView({
            onBack: () => {
              this.goBack();
            },
            onLogout: this.onLogout,
            onOpenLicense: () => {
              this.openView('license');
            }
          })
        } else if (this.currentView === 'license') {
          LicenseView({
            onBack: () => {
              this.goBack();
            }
          })
        } else if (this.currentView === 'notemap') {
          NoteMapView({
            onBack: () => {
              this.goBack();
            },
            onOpenNote: (noteId: string) => {
              this.viewHistory = [];
              this.suppressNoteHistory = true;
              AppStorage.setOrCreate(StateKeys.SELECTED_NOTE_ID, noteId);
              AppStorage.setOrCreate(StateKeys.SELECTED_NOTE_TITLE, '');
              this.lastNoteId = noteId;
              this.suppressNoteHistory = false;
              this.currentView = 'editor';
              this.updateBackAvailable();
            }
          })
        } else {
          ForEach([this.selectedNoteId], (noteId: string) => {
            EditorView({
              onMenu: () => {
                const tick: number = AppStorage.get<number>('TEXT_SELECTION_DISMISS') ?? 0;
                AppStorage.setOrCreate('TEXT_SELECTION_DISMISS', tick + 1);
                this.showDrawer = true;
              },
              onMore: () => {
                this.toast('更多操作：导出、历史与笔记信息');
              },
              onSessionExpired: this.onLogout,
              onDeleted: (parentNoteId: string) => {
                this.suppressNoteHistory = true;
                AppStorage.setOrCreate(StateKeys.SELECTED_NOTE_ID, parentNoteId);
                this.lastNoteId = parentNoteId;
                this.suppressNoteHistory = false;
                this.currentView = 'editor';
                this.updateBackAvailable();
              }
            })
          }, (noteId: string) => noteId)
        }

        if (this.showDrawer) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor($r('app.color.shadow'))
            .opacity(0.34)
            .onClick(() => {
              this.closeDrawer();
            })
        }
      }
      .width('100%')
      .height('100%')
    }
    .sideBarWidth(304)
    .minSideBarWidth(280)
    .maxSideBarWidth(340)
    .showControlButton(false)
    .showSideBar(this.showDrawer)
    .showSideBarWithGesture(false)
    .autoHide(false)
    .divider({ strokeWidth: 0 })
    .onChange((isShown: boolean) => {
      this.showDrawer = isShown;
      if (!isShown) {
        try {
          this.getUIContext().getFocusController().clearFocus();
        } catch (error) {
          // No focused input to clear.
        }
      }
    })
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
    }
    .width('100%')
    .height('100%')
  }
}
