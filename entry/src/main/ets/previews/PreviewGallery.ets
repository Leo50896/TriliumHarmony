import { LoginView } from '../views/LoginView';
import { MainView } from '../views/MainView';
import { SettingsView } from '../views/SettingsView';

/**
 * Dedicated preview entries. They are ignored by the running app but appear as
 * separate cards in DevEco Studio's Previewer, so each design can be inspected
 * without walking through the flow first.
 */
@Preview({ title: '1. 登录页', width: 390, height: 844, colorMode: 'dark' })
@Component
struct LoginPreview {
  build() {
    LoginView()
  }
}

@Preview({ title: '1.1 双因子验证页', width: 390, height: 844, colorMode: 'dark' })
@Component
struct TwoFactorPreview {
  build() {
    LoginView({ initialStep: 2 })
  }
}

@Preview({ title: '2.1 主阅读 / 编辑页', width: 390, height: 844, colorMode: 'dark' })
@Component
struct EditorPreview {
  build() {
    MainView()
  }
}

@Preview({ title: '2.2 设置页', width: 390, height: 844, colorMode: 'dark' })
@Component
struct SettingsPreview {
  build() {
    SettingsView()
  }
}
