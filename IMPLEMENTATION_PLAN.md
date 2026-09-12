# BPHealth 实施计划

## 1. 里程碑与执行顺序
1. 建立 SwiftUI + SwiftData 分层目录与应用入口，保留现有 Web 原型。
2. 实现数据模型、输入校验、可配置血压分类规则引擎和饮食建议规则引擎。
3. 实现 Repository、UseCase、依赖注入容器、统计与 CSV/PDF 导出服务。
4. 实现 Dashboard、Add/Edit、History、Trends、Advice、Profile、Settings、Export、Privacy 页面及导航。
5. 接入通知提醒、LocalAuthentication 锁、本地隐私策略；HealthKit 采用可选适配器并优雅降级。
6. 编写 XCTest 单元测试与 UI 测试骨架，执行可用的本地静态检查；在 macOS/Xcode 上补跑完整 iOS 门禁。
7. 汇总测试结果、已知限制和运行说明，生成 TEST_REPORT.md。

## 2. 文件目录结构
```text
BPHealth/
  BPHealthApp.swift
  Core/Dependency/AppContainer.swift
  Core/Sync/ReadingSyncService.swift（本地空实现，预留 iCloud/CloudKit）
  Models/BPHealthModels.swift
  Domain/Rules.swift
  Data/Persistence.swift
  Core/ViewModels/DashboardViewModel.swift
  Core/UseCases/ExportUseCases.swift
  Core/UseCases/ReadingUseCases.swift
  Services/PlatformServices.swift
  Views/BPHealthViews.swift
  BPHealth.entitlements
  PrivacyInfo.xcprivacy（Apple 隐私清单）
  Resources/{zh-Hans,en}.lproj/Localizable.strings
BPHealthTests/*.swift
BPHealthWatch/README.md（watchOS 预留）
  Package.swift / project.yml
  .github/workflows/ios-ci.yml
  scripts/remote-verify.sh
  scripts/windows-static-check.ps1 / scripts/portable-boundary-check.py
Config/Shared.xcconfig（Bundle Identifier 默认配置）
docs/{architecture,test-plan,medical-disclaimer}.md
README.md / TEST_REPORT.md / CI_REPORT.md
```

## 3. 数据模型
- `BloodPressureReading`: UUID、测量时间、收缩压、舒张压、脉搏、备注、手臂、体位、情绪、运动、是否服药、是否空腹；分类由配置规则引擎实时计算。
- `UserProfile`: 姓名、年龄/出生日期、性别、身高、体重、BMI、怀孕、慢性病、用药、目标范围；分类标准由设置持久化配置。
- 使用 SwiftData `@Model`；Repository 负责排序、搜索、空腹筛选、增删改。

## 4. 血压分类规则引擎
- 规则以 `BPGuideline` 配置，默认中国成人指南，可切换 ACC/AHA。
- 规则按危象、3 级、低血压、2/1 级、正常高值、正常顺序评估；混合极端读数优先高危，返回等级、颜色、解释、紧急标记、建议动作。
- 2–17 岁使用本地可替换的年龄、性别、身高第 90/95 百分位筛查参考；缺少身高、性别、匹配表或年龄小于 3 岁时只返回“需儿科医生评估”；老年人附加个体化目标文案；性别仅影响风险说明。

## 5. 饮食建议规则引擎
- 根据分类、空腹、年龄、性别、BMI、怀孕、肾病/糖尿病/心脏病等生成本地建议。
- 高血压给 DASH、低钠、蔬果、低脂、限酒与体重管理；肾病时禁用高钾建议。
- 高血压危象优先显示复测和急诊评估提示，不用饮食建议替代紧急处理。
- 低血压给补水、适量盐、少食多餐、缓慢起身和症状就医提示；正常给均衡饮食与规律运动。
- 每条建议包含“非诊断，仅供参考”。

## 6. UI 页面与导航
- `NavigationStack`/`TabView` 组合：仪表盘、历史、趋势、建议、我的。
- 提供新增/编辑表单、删除确认、日期选择、空腹开关、趋势图表、统计卡片、设置提醒、导出 CSV/PDF、隐私与免责声明。
- 所有分类、建议、导出页固定显示医疗免责声明；支持中文优先并预留英文本地化。

## 7. 测试计划
- XCTest：边界分类（89/59 至 181/121）、校验、儿童/老人/孕期/肾病、日期时区、SwiftData 持久化、CSV/PDF 导出、饮食规则。
- SwiftUI UI Tests：新增、编辑、删除、搜索筛选、日期、空腹、图表、设置、导出。
- 静态与性能：`xcodebuild build/test/analyze`、SwiftLint（可用时）、10000 条记录滚动与图表基准、VoiceOver/动态字体检查。
- 目标：核心规则覆盖率 ≥90%，整体 ≥80%，零警告；Windows 环境只生成代码并记录 Xcode 门禁待在 macOS 执行。

## 8. 风险与假设
- 当前机器为 Windows，无法安装/运行 Xcode、iOS Simulator、HealthKit entitlement 或真实 Face ID；相关代码采用条件编译/适配器并在报告中标注待 macOS 验证。
- SwiftData/Charts/PDFKit/LocalAuthentication 需 iOS 17 SDK；`Package.swift` 仅用于源码组织，最终应在 Xcode App target 中打开。
- 不存储或上传健康数据；iCloud/HealthKit 为可选扩展点，权限拒绝时回退本地数据。
- 医疗文案仅健康管理参考，所有相关页面固定显示：`本应用不能替代医生诊断，如有不适请及时就医。`

- 工程生成：提供 project.yml，macOS 可用 XcodeGen 生成 App/Unit/UI Test targets。
- 自动验证：GitHub Actions 使用 macOS-15 runner 执行 XcodeGen、build/test/analyze、覆盖率和 Simulator 截图；Windows 不伪造这些结果。
