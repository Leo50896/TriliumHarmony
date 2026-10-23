/**
 * Six visual OTP cells backed by one transparent TextInput. This keeps the
 * native numeric keyboard, paste, and deletion behavior while presenting the
 * familiar six-box 2FA affordance from the design language.
 */
@Component
export struct OtpInput {
  @Link code: string;
  onComplete: () => void = () => {};
  private cells: number[] = [0, 1, 2, 3, 4, 5];

  private isActiveCell(index: number): boolean {
    const cursor: number = this.code.length >= 6 ? 5 : this.code.length;
    return cursor === index;
  }

  build() {
    Stack() {
      Row({ space: 7 }) {
        ForEach(this.cells, (index: number) => {
          Stack({ alignContent: Alignment.Center }) {
            Text(this.code.length > index ? this.code.charAt(index) : '')
              .fontSize(23)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .fontFamily('HarmonyOS Sans')
          }
          .layoutWeight(1)
          .height(58)
          .backgroundColor(this.code.length > index
            ? $r('app.color.bg_surface_alt') : $r('app.color.bg_input'))
          .borderRadius(12)
          .border({
            width: this.isActiveCell(index) ? 1.5 : 1,
            color: this.isActiveCell(index)
              ? $r('app.color.primary') : $r('app.color.border')
          })
        }, (index: number) => index.toString())
      }
      .width('100%')

      TextInput({ text: this.code })
        .width('100%')
        .height(58)
        .maxLength(6)
        .type(InputType.Number)
        .id('trilium-otp-input')
        .defaultFocus(true)
        .focusOnTouch(true)
        .backgroundColor(Color.Transparent)
        .fontColor(Color.Transparent)
        .caretColor(Color.Transparent)
        .selectedBackgroundColor(Color.Transparent)
        .padding(0)
        .onChange((value: string) => {
          const digits: string = value.replace(/[^0-9]/g, '').substring(0, 6);
          this.code = digits;
          if (digits.length === 6) {
            this.onComplete();
          }
        })
    }
    .width('100%')
  }
}
