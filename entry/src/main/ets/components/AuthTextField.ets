import { AppIcon } from './AppIcon';

/**
 * Shared input surface for the login and server fields.
 */
@Component
export struct AuthTextField {
  @Link value: string;
  @Prop placeholder: string = '';
  @Prop icon: Resource = $r('app.media.ic_user');
  @Prop isPassword: boolean = false;
  @Prop inputType: InputType = InputType.Normal;
  @Prop isEnabled: boolean = true;
  @State private revealPassword: boolean = false;
  onSubmitted: () => void = () => {};

  build() {
    Row({ space: 12 }) {
      AppIcon({
        icon: this.icon,
        iconSize: 20,
        tint: $r('app.color.text_secondary'),
        opacityValue: 0.9
      })
      TextInput({ text: this.value, placeholder: this.placeholder })
        .layoutWeight(1)
        .height(54)
        .padding({ left: 0, right: 0 })
        .backgroundColor(Color.Transparent)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .caretColor($r('app.color.primary'))
        .selectedBackgroundColor($r('app.color.primary_soft'))
        .type(this.isPassword
          ? (this.revealPassword ? InputType.Normal : InputType.Password)
          : this.inputType)
        .showPasswordIcon(false)
        .enabled(this.isEnabled)
        .enterKeyType(EnterKeyType.Next)
        .onChange((value: string) => {
          this.value = value;
        })
        .onSubmit(() => {
          this.onSubmitted();
        })
      if (this.isPassword) {
        Stack({ alignContent: Alignment.Center }) {
          AppIcon({
            icon: this.revealPassword ? $r('app.media.ic_eye') : $r('app.media.ic_eye_off'),
            iconSize: 19,
            tint: $r('app.color.text_tertiary')
          })
        }
        .width(34)
        .height(34)
        .borderRadius(17)
        .onClick(() => {
          this.revealPassword = !this.revealPassword;
        })
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 11 })
    .backgroundColor($r('app.color.bg_input'))
    .borderRadius(14)
    .border({ width: 1, color: $r('app.color.border') })
  }
}
