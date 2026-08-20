# SlideBrowser 发布手册（Mac App Store）

本目录之外的所有产物均已就绪：`Resources/Info.plist`（类目 / 加密豁免 / 版权 / LSUIElement）、
`Resources/SlideBrowser.entitlements`（App Sandbox 最小权限）、`Resources/AppIcon.icns`
（含 1024 源图 `icon-source-1024.png`）、隐私政策线上页 <https://slidebrowser.pages.dev/privacy>。
唯一缺口是 **Apple Developer Program 账号与签名证书**（本机当前 0 个签名身份）。

## 一次性准备

1. 加入 Apple Developer Program（99 USD/年），Xcode → Settings → Accounts 登录该 Apple ID。
2. 在 <https://developer.apple.com/account> 确认 Team ID（10 位，形如 `ABCDE12345`）。
3. 把 Team ID 填进两处：
   - `project.yml` → `DEVELOPMENT_TEAM`
   - `Distribution/ExportOptions.plist` → `teamID`
4. App Store Connect → Apps → New App：
   - Bundle ID 选 `app.slidebrowser.mac`（首次需在 developer.apple.com 注册该 identifier）
   - 名称 SlideBrowser，主类目 Productivity
   - 隐私政策 URL：`https://slidebrowser.pages.dev/privacy`
   - App Privacy 问卷全部选 **Data Not Collected**（与代码事实一致：无采集、无三方 SDK）

## 每次发布

```bash
cd SlideBrowser

# 1) 回归测试（69 个用例）
swift test

# 2) 版本号：改 project.yml 里的 MARKETING_VERSION / CURRENT_PROJECT_VERSION，然后重新生成工程
xcodegen generate

# 3) 归档（自动签名，需已登录 Xcode 账号）
xcodebuild -project SlideBrowser.xcodeproj -scheme SlideBrowser \
  -configuration Release archive \
  -archivePath build/SlideBrowser.xcarchive \
  -allowProvisioningUpdates

# 4) 直接上传到 App Store Connect
xcodebuild -exportArchive \
  -archivePath build/SlideBrowser.xcarchive \
  -exportOptionsPlist Distribution/ExportOptions.plist \
  -exportPath build/export \
  -allowProvisioningUpdates
```

上传完成后在 App Store Connect 选择该构建、填写 What's New、提交审核。

## 审核注意事项（本 App 特有）

- **LSUIElement 无主窗口**：在 Review Notes 写明使用方式，否则审核员会认为 App 无法打开：
  “Menu bar utility. Click the sidebar icon in the menu bar, or press ⌘E anywhere,
  to slide the browser panel in from the screen edge. Esc dismisses it.”
- **审核截图**：面板呼出状态的全屏截图（App Store 要求 2560×1600 或 2880×1800 等尺寸），
  官网素材 `website/assets/panel-favourites.png` 可作为构图参考，但需按要求尺寸重截。
- **默认站点列表**含 ChatGPT/Gmail 等第三方商标名，若被质询可说明它们只是用户可删改的书签默认值。
- 加密问卷已通过 `ITSAppUsesNonExemptEncryption=false` 预答，无需每次再填。

## 与日常开发的关系

- 日常开发仍用 `./build.sh --debug`（SwiftPM + ad-hoc 签名），不依赖 Xcode 工程。
- `SlideBrowser.xcodeproj` 是 `xcodegen generate` 的产物，**以 `project.yml` 为事实源**，
  不要手改工程文件。
- 未签名流水线已验证可用：`archive CODE_SIGNING_ALLOWED=NO` 能产出完整 .app，
  说明填入 Team ID 后剩余步骤只差证书。
