import { AppIcon } from './AppIcon';
import { AuthSession } from '../models/AuthModels';
import { SearchResultItem } from '../models/SearchModels';
import { SessionStore } from '../services/SessionStore';
import { SearchService } from '../services/SearchService';

/**
 * Global note search. It is hosted in a bindSheet by EditorView.
 * Results carry title, ancestor path and a content snippet; selecting one
 * closes the sheet and writes nav.selectedNoteId through the parent callback.
 */
@Component
export struct SearchView {
  onClose: () => void = () => {};
  onSelect: (noteId: string) => void = () => {};

  @State private query: string = '';
  @State private results: SearchResultItem[] = [];
  @State private isSearching: boolean = false;
  @State private hasSearched: boolean = false;
  @State private errorMessage: string = '';

  private searchTimer: number = -1;
  private focusTimer: number = -1;
  private searchSequence: number = 0;

  aboutToAppear(): void {
    this.requestInputFocus(320);
  }

  aboutToDisappear(): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
    if (this.focusTimer >= 0) {
      clearTimeout(this.focusTimer);
      this.focusTimer = -1;
    }
  }

  private requestInputFocus(delay: number): void {
    if (this.focusTimer >= 0) {
      clearTimeout(this.focusTimer);
    }
    this.focusTimer = setTimeout(() => {
      this.focusTimer = -1;
      try {
        this.getUIContext().getFocusController().requestFocus('globalSearchInput');
      } catch (error) {
        // The sheet may still be in its opening animation.
      }
    }, delay);
  }

  private scheduleSearch(): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
    const value: string = this.query.trim();
    if (value.length === 0) {
      this.searchSequence++;
      this.results = [];
      this.hasSearched = false;
      this.isSearching = false;
      this.errorMessage = '';
      return;
    }
    this.searchTimer = setTimeout(() => {
      this.searchTimer = -1;
      this.performSearch();
    }, 380);
  }

  private async performSearch(): Promise<void> {
    const value: string = this.query.trim();
    if (value.length === 0) {
      return;
    }
    const sequence: number = ++this.searchSequence;
    this.isSearching = true;
    this.hasSearched = true;
    this.errorMessage = '';

    const session: AuthSession | null = SessionStore.currentSession();
    if (session === null) {
      this.isSearching = false;
      this.errorMessage = '登录状态已失效';
      return;
    }

    try {
      const items: SearchResultItem[] = await SearchService.search(session, value);
      if (sequence !== this.searchSequence) {
        return;
      }
      this.results = items;
    } catch (error) {
      if (sequence !== this.searchSequence) {
        return;
      }
      if (error instanceof Error && error.message === 'AUTH_401') {
        this.errorMessage = '登录状态已失效';
        this.onClose();
        return;
      }
      this.errorMessage = '搜索失败，请检查网络后重试';
      this.results = [];
    } finally {
      if (sequence === this.searchSequence) {
        this.isSearching = false;
      }
    }
  }

  private clearQuery(): void {
    this.query = '';
    this.results = [];
    this.hasSearched = false;
    this.isSearching = false;
    this.errorMessage = '';
    this.searchSequence++;
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
  }

  private typeIcon(type: string): Resource {
    if (type === 'code') {
      return $r('app.media.ic_code');
    }
    if (type === 'book') {
      return $r('app.media.ic_book');
    }
    return $r('app.media.ic_doc');
  }

  @Builder
  private SearchResultRow(item: SearchResultItem) {
    Row({ space: 11 }) {
      Stack({ alignContent: Alignment.Center }) {
        AppIcon({
          icon: this.typeIcon(item.type),
          iconSize: 18,
          tint: $r('app.color.text_secondary')
        })
      }
      .width(34)
      .height(34)
      .borderRadius(9)
      .backgroundColor($r('app.color.bg_primary'))
      .alignSelf(ItemAlign.Start)

      Column({ space: 4 }) {
        Row({ space: 5 }) {
          Text(item.title.length > 0 ? item.title : '未命名笔记')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (item.isProtected) {
            AppIcon({
              icon: $r('app.media.ic_lock'),
              iconSize: 13,
              tint: $r('app.color.text_tertiary')
            })
          }
        }
        .width('100%')

        Text(item.path.length > 0 ? item.path : '根目录')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (item.snippet.length > 0) {
          Text(item.snippet)
            .fontSize(13)
            .lineHeight(20)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        } else if (item.type === 'text' || item.type === 'code') {
          Text('暂无正文片段')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(13)
    .backgroundColor($r('app.color.bg_secondary'))
    .borderRadius(11)
    .alignItems(VerticalAlign.Top)
    .onClick(() => {
      this.onSelect(item.noteId);
    })
  }

  build() {
    Column() {
      Row() {
        Text('搜索')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text('×')
          .fontSize(24)
          .fontColor($r('app.color.text_secondary'))
          .width(38)
          .height(38)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.onClose();
          })
      }
      .width('100%')
      .height(44)

      Row({ space: 8 }) {
        AppIcon({
          icon: $r('app.media.ic_search'),
          iconSize: 18,
          tint: $r('app.color.text_tertiary')
        })
        TextInput({ placeholder: '搜索标题、正文或标签', text: this.query })
          .id('globalSearchInput')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .caretColor($r('app.color.primary'))
          .backgroundColor(Color.Transparent)
          .padding(0)
          .defaultFocus(true)
          .onAppear(() => {
            this.requestInputFocus(80);
          })
          .onChange((value: string) => {
            this.query = value;
            this.scheduleSearch();
          })
          .onSubmit(() => {
            if (this.searchTimer >= 0) {
              clearTimeout(this.searchTimer);
              this.searchTimer = -1;
            }
            this.performSearch();
          })
        if (this.query.length > 0) {
          Text('×')
            .fontSize(18)
            .fontColor($r('app.color.text_tertiary'))
            .width(32)
            .height(32)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.clearQuery();
            })
        }
      }
      .width('100%')
      .height(46)
      .padding({ left: 13, right: 8 })
      .margin({ top: 10, bottom: 12 })
      .backgroundColor($r('app.color.bg_secondary'))
      .borderRadius(23)

      if (this.isSearching) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(26)
            .height(26)
            .color($r('app.color.primary'))
          Text('正在搜索并整理匹配片段…')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Start)
        .padding({ top: 46 })
      } else if (this.errorMessage.length > 0) {
        Column({ space: 10 }) {
          Text(this.errorMessage)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          Text('重试')
            .fontSize(14)
            .fontColor($r('app.color.primary'))
            .onClick(() => {
              this.performSearch();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Start)
        .padding({ top: 46 })
      } else if (!this.hasSearched) {
        Column({ space: 12 }) {
          AppIcon({
            icon: $r('app.media.ic_search'),
            iconSize: 34,
            tint: $r('app.color.text_tertiary')
          })
          Text('搜索你的知识库')
            .fontSize(16)
            .fontColor($r('app.color.text_secondary'))
          Text('支持标题、正文和标签，结果会显示所在路径与匹配片段')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .textAlign(TextAlign.Center)
            .width('78%')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Start)
        .padding({ top: 46 })
      } else if (this.results.length === 0) {
        Column({ space: 10 }) {
          Text('没有找到匹配的笔记')
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
          Text('换个关键词试试')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Start)
        .padding({ top: 46 })
      } else {
        Row() {
          Text(`找到 ${this.results.length} 条`)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
          Blank()
          Text('仅显示前 12 条')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .visibility(this.results.length >= 12 ? Visibility.Visible : Visibility.Hidden)
        }
        .width('100%')
        .margin({ bottom: 8 })

        List({ space: 8 }) {
          ForEach(this.results, (item: SearchResultItem) => {
            ListItem() {
              this.SearchResultRow(item)
            }
          }, (item: SearchResultItem) => item.noteId)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 10, bottom: 14 })
    .backgroundColor($r('app.color.bg_primary'))
  }
}
