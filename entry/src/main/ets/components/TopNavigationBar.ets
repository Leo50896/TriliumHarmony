import { AppIcon } from './AppIcon';

/**
 * Reusable breadcrumb navigation bar used by the note reader.
 * The trailing actions are callbacks so the bar has no dependency on routing.
 */
@Component
export struct TopNavigationBar {
  @Prop crumbs: string[] = [];
  @Prop activeCrumb: string = '';
  @Prop showOutline: boolean = false;
  @Prop loading: boolean = false;
  onMenu: () => void = () => {};
  onSearch: () => void = () => {};
  onMore: () => void = () => {};
  onDelete: () => void = () => {};
  onOutline: () => void = () => {};
  onTitle: () => void = () => {};

  @Builder
  IconButton(icon: Resource, action: () => void) {
    Stack({ alignContent: Alignment.Center }) {
      AppIcon({ icon: icon, iconSize: 21, tint: $r('app.color.text_primary') })
    }
    .width(38)
    .height(38)
    .borderRadius(19)
    .onClick(action)
  }

  build() {
    Row({ space: 2 }) {
      this.IconButton($r('app.media.ic_menu'), this.onMenu)
      Row({ space: 3 }) {
        ForEach(this.crumbs, (crumb: string, index: number) => {
          Row({ space: 2 }) {
            Text(crumb)
              .fontSize(15)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (index < this.crumbs.length - 1) {
              AppIcon({
                icon: $r('app.media.ic_chevron_right'),
                iconSize: 12,
                tint: $r('app.color.text_tertiary')
              })
            }
          }
        }, (crumb: string) => crumb)
        if (this.activeCrumb.length > 0) {
          if (this.crumbs.length > 0) {
            AppIcon({
              icon: $r('app.media.ic_chevron_right'),
              iconSize: 12,
              tint: $r('app.color.text_tertiary')
            })
              .margin({ left: 2 })
          }
          Text(this.activeCrumb)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ left: 3 })
            .onClick(() => {
              this.onTitle();
            })
        }
      }
      .layoutWeight(1)
      .height('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 6, right: 8 })
      .margin({ left: 4, right: 6 })
      .clip(true)
      .onClick(() => {
        this.onTitle();
      })

      if (this.loading) {
        LoadingProgress()
          .width(16)
          .height(16)
          .color($r('app.color.primary'))
          .margin({ right: 4 })
      }
      if (this.showOutline) {
        this.IconButton($r('app.media.ic_checklist'), this.onOutline)
      }
      this.IconButton($r('app.media.ic_search'), this.onSearch)
      Stack({ alignContent: Alignment.Center }) {
        AppIcon({ icon: $r('app.media.ic_more'), iconSize: 21, tint: $r('app.color.text_primary') })
      }
      .width(38)
      .height(38)
      .borderRadius(19)
      .bindMenu([
        {
          value: '删除笔记',
          action: () => {
            this.onDelete();
          }
        }
      ])
    }
    .width('100%')
    .height(56)
    .padding({ left: 8, right: 8 })
    .backgroundColor($r('app.color.bg_primary'))
  }
}
