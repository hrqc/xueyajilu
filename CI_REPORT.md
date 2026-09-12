# BPHealth CI 报告

当前 Windows 开发环境没有 macOS、Xcode 或 iOS Simulator，因此本文件在本地仅作为 CI 结果入口，未伪造通过状态。

GitHub Actions 工作流位于 `.github/workflows/ios-ci.yml`，会在 `macos-15` 上执行：

- XcodeGen 工程生成与工程列表检查
- `xcodebuild build`
- XCTest 与 UI Test（启用代码覆盖率）
- `xcodebuild analyze`
- SwiftLint JSON 报告（作为辅助质量信号）
- 编译/分析警告数与 XCTest 摘要
- iPhone Simulator 启动与 UI 截图
- 代码覆盖率门禁：规则文件 ≥90%，整体 ≥80%；Swift 警告按错误处理

运行完成后，工作流会用真实的 Build、测试、分析、覆盖率和截图结果覆盖此报告，并上传 `artifacts/` 与 `screenshots/`。
