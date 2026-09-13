# 测试计划

## 单元测试

- 分类边界：89/59、90/60、119/79、120/80、129/79、130/80、139/89、140/90、160/100、180/120、181/121。
- 输入校验：收缩压 50–300、舒张压 30–200、收缩压大于舒张压、脉搏 30–250、未来日期警告；ReadingUseCase 与表单双层校验。
- 特殊人群：儿童无身高、老人个体化提示、孕期资料、肾病抑制高钾建议、糖尿病资料保留。
- 持久化与导出：SwiftData 增删改查、时间排序、搜索/空腹筛选、CSV 转义；PDF 在 iOS target 使用 PDFKit 验证。
- 补充边界与统计：129/79、130/80，分类安全元数据，BMI/年龄与老人提示，年龄输入与出生日期互斥持久化，CSV 引号转义及中英文表头，目标达标率和晨间/晚间平均。

- 日期与时区：使用注入的 UTC Calendar 验证出生日期 17/18 岁生日边界、晨间/晚间统计和 CSV 时间排序。

- 平台失败路径：通过注入 `NotificationServicing`、`AuthenticationServicing`、`HealthKitServicing` mock 验证拒绝、不可用和写入失败不崩溃。

## UI 测试

新增、编辑、删除记录；DatePicker 与未来时间提示；空腹开关；历史搜索和筛选；趋势时间范围与图表；年龄/出生日期资料入口；建议、设置提醒、Face ID、导出、隐私页；VoiceOver 标签、动态字体和深色模式。

## 性能与门禁

在 macOS 上执行 `xcodebuild build -scheme BPHealth -destination 'platform=iOS Simulator,name=iPhone 15'`、`xcodebuild test`、`xcodebuild analyze`；以 10000 条记录进行列表滚动和图表基准，`TrendSampler` 将趋势图限制到最多 500 点，统计仍使用完整数据，目标核心规则覆盖率 ≥90%、整体 ≥80%、零编译警告。Windows 仅能进行源码静态检查。

## 当前审计限制

SwiftUI 界面使用注入 SwiftData `ModelContext` 的 `BPUIStore`，启动时加载记录与资料；仍需在 macOS target 验证迁移、异常恢复和并发行为。导出页 PDF 分享、提醒授权、Face ID/Touch ID、HealthKit 读写流程必须通过 UI/真机测试。儿科分支覆盖内置中国 3–17 岁筛查参考和可注入百分位表的第 90/95 百分位，缺少匹配数据时只提示儿科评估，避免自行诊断；孕期、糖尿病和 BMI 已有本地提示规则。

## Windows 静态门禁

运行 `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/windows-static-check.ps1`，验证必需文件、页面、免责声明、Swift 禁用 API、括号、entitlements、LF 换行、Node 语法、Bash 语法和 `scripts/portable-boundary-check.py` 的 12 个边界语义烟测。

## macOS 自动门禁

`.github/workflows/ios-ci.yml` 在 `macos-15` 运行 XcodeGen、`xcodebuild build/test/analyze`、代码覆盖率和 iPhone Simulator 截图；`scripts/remote-verify.sh` 将真实状态写入 `CI_REPORT.md` 并上传日志与 `.xcresult`。

## 个人侧载构建门禁

`.github/workflows/ios-portable-ipa.yml` 在 macOS-15 上以 `iphoneos` SDK 编译 `BPHealthPortable`，使用 warnings-as-errors 和无签名模式生成 unsigned IPA。门禁检查 Payload 结构、Bundle Identifier、构建成功状态以及便携版不链接 HealthKit framework、不包含 `embedded.mobileprovision`；该工件需要在 Windows Sideloadly 中由用户本地重签，不能作为已签名发布包使用。
