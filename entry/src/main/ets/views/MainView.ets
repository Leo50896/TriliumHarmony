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
  @StorageProp(StateKeys.SELECTED_NOTE_ID) private selectedNoteId: string = '';

  private onDrawerVisibilityChanged(): void {
    const tick: number = AppStorage.get<number>('TEXT_SELECTION_DISMISS') ?? 0;
    AppStorage.setOrCreate('TEXT_SELECTION_DISMISS', tick + 1);
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
          this.currentView = 'editor';
          this.closeDrawer();
          AppStorage.setOrCreate(StateKeys.OPEN_GLOBAL_SEARCH, true);
        },
        onOpenNote: (noteId: string, title: string) => {
          this.currentView = 'editor';
          this.closeDrawer();
        },
        onOpenSettings: () => {
          this.currentView = 'settings';
          this.closeDrawer();
        },
        onOpenNoteMap: () => {
          this.currentView = 'notemap';
          this.closeDrawer();
        },
        onNewNote: () => {
          this.closeDrawer();
          this.currentView = 'editor';
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
              this.currentView = 'editor';
            },
            onLogout: this.onLogout,
            onOpenLicense: () => {
              this.currentView = 'license';
            }
          })
        } else if (this.currentView === 'license') {
          LicenseView({
            onBack: () => {
              this.currentView = 'settings';
            }
          })
        } else if (this.currentView === 'notemap') {
          NoteMapView({
            onBack: () => {
              this.currentView = 'editor';
            },
            onOpenNote: (noteId: string) => {
              AppStorage.setOrCreate(StateKeys.SELECTED_NOTE_ID, noteId);
              AppStorage.setOrCreate(StateKeys.SELECTED_NOTE_TITLE, '');
              this.currentView = 'editor';
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
                AppStorage.setOrCreate(StateKeys.SELECTED_NOTE_ID, parentNoteId);
                this.currentView = 'editor';
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
