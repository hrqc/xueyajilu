# BPHealth

BPHealth 是面向 iPhone（iOS 17+）的本地优先血压记录与健康管理 App，使用 SwiftUI、SwiftData、Swift Charts、UserNotifications 和 LocalAuthentication，并为 HealthKit/iCloud 预留适配点。规则与数据核心保持可共享结构，后续可增加 watchOS target。

## 目录

- `IMPLEMENTATION_PLAN.md`：实施计划与边界
- `BPHealth/`：SwiftUI App、SwiftData 模型、规则引擎、服务与页面
- `BPHealth/Core/Sync/`：本地空同步实现与未来 iCloud/CloudKit 扩展边界
- `BPHealthWatch/`：watchOS 架构预留说明
- `BPHealthTests/`：规则与输入校验 XCTest、启动/新增/编辑/删除/隐私入口 UI 测试
- `docs/architecture.md`：架构说明
- `docs/test-plan.md`：测试计划
- `docs/medical-disclaimer.md`：医疗免责声明
- `TEST_REPORT.md`：当前验证结果
- `CI_REPORT.md`：macOS CI 最终结果入口（运行 34673382905 已通过）
- `app.js` / `index.html` / `styles.css`：早期 Web 原型，仅用于交互参考，不属于 iOS 医疗数据交付；已移除外部字体请求。

## 在 macOS/Xcode 运行

1. 在 Xcode 15+ 创建 iOS App target，Bundle Identifier 设为 `com.example.bphealth`，最低系统设为 iOS 17.0。
2. 或在 macOS 安装 XcodeGen 后运行 `xcodegen generate`，使用仓库中的 `project.yml` 自动生成 target、测试 scheme、HealthKit entitlement 和用途说明。
   Bundle Identifier 默认来自 `Config/Shared.xcconfig` 的 `BPHEALTH_BUNDLE_ID`（`com.example.bphealth`）；发布或多环境构建时可在本地/CI xcconfig 覆盖该值。
3. 在模拟器或真机运行 `BPHealthApp.swift`，再执行 `Product > Test`。
4. 如需 HealthKit，使用生成的 entitlement，并在 Apple Developer Signing 中启用 HealthKit；运行时由用户授予最小权限。

## Windows 静态门禁

在当前 Windows 环境可运行 `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/windows-static-check.ps1`，检查交付物、Swift 禁用 API、花括号、免责声明、换行、Node、Bash 语法和 12 个便携边界语义烟测；这不能替代 macOS 的 Xcode 编译和 XCTest。

## Windows + iPhone 个人侧载

仓库提供 `BPHealthPortable` 个人侧载 target，Bundle Identifier 为 `com.hrqc.bphealth.personal`。该版本关闭 HealthKit entitlement、HealthKit framework 和设置页 HealthKit 控件，保留本地记录、趋势、统计、CSV/PDF、提醒、Face ID/Touch ID 与加密备份。

1. 打开 GitHub Actions 的 `Build BPHealth Portable IPA` 工作流并点击 **Run workflow**。
2. 等待 macOS runner 完成，下载 artifact `bphealth-portable-ipa` 中的 `BPHealthPortable-unsigned.ipa`。
3. 在 Windows 安装 [Sideloadly](https://sideloadly.io/) 及其要求的官方 Windows 版 iTunes/iCloud，将 iPhone 连接到电脑并信任设备。
4. 将 unsigned IPA 拖入 Sideloadly，在 Sideloadly 本机输入你自己的 Apple ID，点击 Start 完成重签和安装。
5. 首次启动若提示信任开发者，到 iPhone“设置 → 通用 → VPN 与设备管理”完成信任。

GitHub artifact 是**未签名的 iphoneos IPA**，不能直接安装；Apple ID、密码和验证码不要提交到 GitHub 或发送给 Codex。免费 Apple ID 侧载有效期较短，需要定期重新签名。个人侧载版不包含 HealthKit；如需 HealthKit、TestFlight 或 App Store 发布，需要付费 Apple Developer Team 和正式 `BPHealth` target。

## Windows 现状

开发工作区为 Windows；真实 iOS 验证已由 GitHub Actions macOS runner 完成（运行 34673382905：54/54 测试、覆盖率 80.08%、规则 93.71%、警告 0）。Face ID/Touch ID、HealthKit 和 VoiceOver 仍需真机复核。Web 原型使用浏览器 localStorage，不应存放真实敏感健康数据；正式健康数据请使用 iOS App。

## 数据与医疗安全

数据默认保存在设备本地；不会调用在线 AI，也不会自动上传。所有分类、建议和导出页面显示：**本应用不能替代医生诊断，如有不适请及时就医。**


## 语言
已提供简体中文和 English 本地化资源，默认界面使用简体中文；设置页提供语言选择器，主要页面标题、表单、筛选、导出和设置控件会随语言切换；医疗免责声明与关键安全提示保留中文原文，确保符合产品安全要求。

本地隐私：SwiftData 默认仅保存在设备沙盒，应用 entitlement 已启用 iOS Data Protection（Complete），Face ID/Touch ID 锁定入口使用 LocalAuthentication。导出页提供 AES-GCM/Keychain 加密备份；HealthKit 写入为显式可选开关，权限拒绝时保留本地数据并优雅降级。


## 生成 Xcode 工程（可选）
仓库提供 project.yml；在 macOS 安装 XcodeGen 后运行 xcodegen generate，即可生成 BPHealth.xcodeproj，再执行 xcodebuild。
GitHub Actions 的 `.github/workflows/ios-ci.yml` 会自动调用 `scripts/remote-verify.sh`，运行 build、XCTest/UI Test、analyze、覆盖率和 Simulator 截图；脚本会强制规则文件覆盖率 ≥90%、整体覆盖率 ≥80%，并将 Swift 警告按错误处理。
仓库同时包含 `BPHealth/PrivacyInfo.xcprivacy`：默认不跟踪、不向第三方上传数据，也不声明收集个人数据；UserDefaults 用于本地设置保存。提交 App Store 前仍需在 App Store Connect 和真实构建产物中复核隐私问卷与权限说明。
