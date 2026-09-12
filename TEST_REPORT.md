# BPHealth 测试报告

## 执行环境

- 日期：2026-09-12
- 环境：Windows 工作区；未安装 Xcode/Swift/iOS Simulator
- 已运行：`git status --short`、源码文件扫描、规则与文档静态检查

## 用例结果

| 用例 | 结果 | 证据/限制 |
|---|---|---|
| 实施计划与目录 | 通过 | `IMPLEMENTATION_PLAN.md` 已生成 |
| 成人分类边界 | 已编写 | `BPHealthTests/BPHealthRuleTests.swift`；需 macOS XCTest 执行 |
| 输入校验与未来日期 | 已编写 | `ReadingValidator` 与 XCTest；需 macOS 执行 |
| 儿童缺身高/百分位 | 已编写 | 缺身高提示儿科评估；内置 3–17 岁筛查参考与可配置第 90/95 百分位阈值测试；需 macOS 执行 |
| 肾病饮食规则 | 已编写 | 不生成高钾建议；需 macOS 执行 |
| AES-GCM 加密备份往返 | 已编写（CryptoKit/Security 条件测试） | 需 macOS/iOS XCTest 执行 |
| 129/79、130/80 分类边界 | 已编写 | `BPHealthTests/BPHealthRuleTests.swift`；需 macOS XCTest 执行 |
| 分类安全元数据 | 已编写 | 验证颜色名、解释、动作和危象紧急标记；需 macOS XCTest 执行 |
| 用户资料 BMI/年龄及老人提示 | 已编写 | 验证 BMI、年龄覆盖值和个体化文案；需 macOS XCTest 执行 |
| CSV 引号转义与时间排序 | 已编写 | 验证逗号/引号备注和升序导出；需 macOS XCTest 执行 |
| 目标达标率、晨间/晚间统计 | 已编写 | `DashboardStats` 单元测试；需 macOS XCTest 执行 |
| SwiftData 持久化/CRUD/搜索/空腹筛选 | 已编写内存容器 XCTest | Windows 无 SwiftData runtime，需 macOS XCTest 执行 |
| CSV 导出/PDF 生成 | 已实现并已编写 XCTest | Windows 无 UIKit/PDF runtime，需 macOS XCTest 执行 |
| UI 启动/新增/编辑/删除/时间选择/空腹/趋势/建议/导出/隐私入口 | 已实现测试用例；`-ui-testing` 使用内存 SwiftData 容器隔离测试 | Windows 无法运行 Simulator，仍待 macOS 执行 |
| xcodebuild build/test/analyze | 未执行 | 当前系统无 Xcode |
| 覆盖率 ≥90%/≥80% | 未测量 | 需 `xcodebuild test -enableCodeCoverage YES` |
| 10000 条统计性能 | 已编写 XCTest `measure` 用例 | 真实耗时仍需 Instruments/Simulator |

## 已知限制

1. `BPHealthApp` 使用 SwiftData 容器；需在 Xcode App target 中加入所有 Swift 文件并设置 iOS 17。
2. 新增资料字段（姓名、其他慢性病）需要在已有生产数据上通过 SwiftData `SchemaMigrationPlan` 验证；全新安装不受影响。
3. HealthKit、Face ID、UserNotifications 权限和 PDFKit 导出必须在 macOS 真机/模拟器验证。
4. App 已在入口通过 `AppContainer` 注入 SwiftData 与通知、认证、HealthKit 服务到 `BPUIStore`，并提供资料保存；仍需 iOS runtime 验证迁移和异常恢复。
5. PDF、通知、Face ID、HealthKit 权限与读取流程已接入源码，但仍需 macOS 真机/模拟器验证。
6. 不能在本环境宣称“零警告、全绿或覆盖率达标”；这些是待 macOS 门禁的明确事项。
7. 儿科规则当前在缺少可靠百分位数据时返回需医生评估提示，未自行诊断；饮食规则已覆盖 BMI、孕期和糖尿病的提示。

## 修复记录

- 修复 Profile 页身高/体重 Binding，使其与 `Double` 类型一致。
- 修复导出和隐私页字符串中的换行，确保 Swift 字符串语法有效。
- 避免业务代码使用 `try!`/`fatalError`；容器创建失败时显示可恢复提示。

医疗免责声明核验：源码中 Dashboard、Add/Edit、History、Trends、Advice、Export、Privacy 页面显示‘本应用不能替代医生诊断，如有不适请及时就医。’。

静态检查结果：Node app.js 语法检查通过；Python 交付物/免责声明/禁用 API 检查通过；便携边界检查 12/12 通过（不替代 XCTest）。

## 最后一轮（Windows 静态门禁）

- 修改文件：`BPHealth/Domain/Rules.swift`、`BPHealth/Views/BPHealthViews.swift`、`BPHealth/Models/BPHealthModels.swift`、`BPHealth/Services/PlatformServices.swift`、`BPHealth/Core/*`、`Package.swift`、文档。
- 执行命令：`node --check app.js`；Python 交付物/免责声明/禁用 API 检查；边界规则替代测试。
- 结果：Node 语法通过；静态门禁通过；12 个便携血压边界用例通过；未发现 `fatalError`、`try!` 或强制解包模式。
- Xcode 门禁：仍需在 macOS 执行 `xcodebuild build/test/analyze`、UI 测试、覆盖率、Instruments 性能和 HealthKit/Face ID 权限测试。

新增验证说明：SwiftData 启动加载、记录 CRUD、资料保存、PDF 生成入口、提醒取消、Face ID/HealthKit 权限入口和 HealthKit 读取适配均已落地源码；因 Windows 无 iOS runtime，仍待 macOS 执行。


## 继续修复后的静态门禁

- `node --check app.js`：通过。
- Python 交付物、免责声明、禁用 API、Swift 文件完整性检查：通过。
- 便携边界替代测试：12/12 通过（仅用于静态语义烟测）。
- 本轮修复：SwiftData 启动加载与资料保存、未来时间保存警告、非空腹筛选、CSV 转义、分页 PDF、规则切换、提醒/Face ID/HealthKit 入口、Advice 动态规则、趋势脉搏线与 Dashboard 达标统计。
- 仍需 macOS：真实 Swift 编译、XCTest/UI Test、覆盖率、xcodebuild analyze、性能、权限和可访问性。

新增：App 锁定遮罩、HealthKit 最近数据读取按钮和本地化资源已加入源码；仍需真机权限验证。

- 可选工程生成：新增 project.yml，macOS 安装 XcodeGen 后可生成 BPHealth.xcodeproj；Windows 未执行 XcodeGen。

本轮新增：可配置儿科百分位评估器、本地 AES-GCM/Keychain 加密服务、`NSFileProtectionComplete` entitlement、可选 HealthKit 写入开关、AppContainer 依赖注入和 SwiftPM HealthKit linker 设置；均需 iOS SDK 和真机权限环境验证。

- 最后静态检查：Swift 源文件 13 个，未发现 `fatalError`、`try!`、`NSImage` 或错误双反斜杠；Node JS 语法通过。

最终补充：儿科百分位评估器、AES-GCM/Keychain 适配器、加密备份导出和设置页语言选择器已加入；静态门禁再次通过。SwiftData 主存储仍依赖系统数据保护，应用层加密目前覆盖显式加密备份流程。

## 2026-09-11 最终静态门禁

- 修复 `project.yml` 中的换行转义，补充 HealthKit framework、entitlements、用途说明，并将单元/UI 测试加入 scheme 测试目标。
- 修复 HealthKit 授权与血压相关样本的显式集合类型，避免 Swift SDK 泛型不匹配。
- 目标血压范围字段已支持 `收缩压下限-上限/舒张压下限-上限` 格式，并参与仪表盘达标率和 SwiftData 资料保存。
- CSV 导出已包含手臂、体位、情绪、测量前运动和服药状态等可选记录字段。
- `node --check app.js`：通过。
- Python 静态门禁：通过（必需交付物、免责声明、禁用 API、测试模块导入、HealthKit entitlement）。
- 便携 Python 边界检查：12/12 通过（包含 89/59、180/120、181/121 和混合极端读数；不替代 XCTest）。
- Windows 环境仍缺少 Swift/Xcode/XcodeGen，因此真实编译、XCTest/UI Test、覆盖率、analyze、Instruments 性能和权限测试未执行。
- 已新增 `.github/workflows/ios-ci.yml` 与 `scripts/remote-verify.sh`；待仓库连接 GitHub 并触发 macOS runner 后，真实结果会写入 `CI_REPORT.md`。
- CI 同时生成 SwiftLint JSON 辅助报告；SwiftLint 不在 Windows 本地伪造执行结果。
- 最近补充：HealthKit 可选写入开关、HealthKit 导入/导出、低血压适量盐分与避免久站建议、成人性别风险说明、2 岁以下儿科保护、老年个体化建议和 10000 条统计性能用例。
- CSV/PDF 与加密备份均保留手臂、体位、情绪、运动、服药、空腹和备注字段。
- CI 门禁已加强：`remote-verify.sh` 对 `xcodebuild` 启用 `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` 与 `GCC_TREAT_WARNINGS_AS_ERRORS=YES`，通过 `xccov --json` 强制规则文件 ≥90%、整体 ≥80%，无可用 Simulator 时立即失败并写明原因。
- 可访问性补强：仪表盘趋势图、趋势统计容器和统计卡片增加 VoiceOver label；提醒权限拒绝时自动回滚开关，避免显示虚假的已启用状态。

BPHealthRuleTests 使用 #if SWIFT_PACKAGE 区分 SwiftPM 的 BPHealthCore 与 XcodeGen App target 的 BPHealth 模块，避免 CI 测试模块解析差异。


## 本轮（继续执行）

- 修改文件：`BPHealth/BPHealthApp.swift`、`BPHealth/Views/BPHealthViews.swift`、`BPHealth/Core/Dependency/AppContainer.swift`、`BPHealthTests/BPHealthRuleTests.swift`、`Package.swift`、`project.yml`、`scripts/remote-verify.sh`、`.gitattributes`、`TEST_REPORT.md`。
- 修改内容：AppContainer 从应用入口注入 BPUIStore；设置页、Dashboard、History、Advice 共用注入的规则/饮食引擎；历史列表随指南切换实时重算；显式化 SwiftData 谓词目标 ID；修复 persist 未使用变量风险；SwiftPM/XcodeGen 测试模块导入分支；声明 SwiftPM HealthKit linker。
- 执行命令：`node --check app.js`、Git Bash `bash -n scripts/remote-verify.sh`、PowerShell XML entitlement 解析、Swift 禁用 API/括号平衡/交付物静态扫描、`python scripts/portable-boundary-check.py`。
- 结果：Node、Bash、entitlements、禁用 API、括号平衡、交付物检查通过；便携边界检查 12/12 通过。
- 环境失败原因：当前 Windows 没有 `swift`、`swiftc`、`xcodebuild`、`xcodegen`、`swiftlint` 和 iOS Simulator，无法执行真实编译、XCTest/UI Test、覆盖率、analyze 或权限测试。
- 修复方案：已将完整 macOS 门禁写入 `.github/workflows/ios-ci.yml` 与 `scripts/remote-verify.sh`；连接 GitHub 后在 macOS runner 生成工程并执行真实门禁，结果覆盖 `CI_REPORT.md`。
scripts/remote-verify.sh 与 project.yml 已统一为 LF，避免 macOS Bash 读取 CRLF 产生伪命令错误。


- 工程卫生：新增 `.gitattributes`，将 shell、YAML、Swift 和文档统一为 LF；CI 脚本同时启用 Swift/GCC warnings-as-errors。

## 本轮增量（规则注入与 CI 稳定性）

- 修改文件：`BPHealth/Core/Dependency/AppContainer.swift`、`BPHealth/Views/BPHealthViews.swift`、`BPHealthTests/BPHealthUITests.swift`、`project.yml`、`scripts/remote-verify.sh`、`.gitattributes`、`docs/architecture.md`。
- 修改内容：统一注入 RuleEngine/DietaryAdviceRuleEngine；指南切换后历史、仪表盘和建议实时使用新规则；补充设置页 UI 测试；动态字体和对比度细节优化；提醒授权竞态保护；统一 LF 换行；工程和命令行门禁均开启 Swift/GCC warnings-as-errors。
- 执行命令：`bash -n scripts/remote-verify.sh`、`node --check app.js`、Swift 禁用 API/括号平衡扫描、交付物/免责声明扫描、换行扫描。
- 结果：全部静态检查通过。
- 未执行：当前 Windows 仍无 Xcode、Swift、Simulator，真实编译、XCTest/UI Test、覆盖率和 analyze 必须由 macOS CI 完成。

## 最终静态门禁（本轮）

- `bash -n scripts/remote-verify.sh`：通过。
- `node --check app.js`：通过。
- Swift 禁用 API、括号平衡、entitlements XML、交付物和免责声明扫描：通过。
- 所有文本文件 LF 换行扫描：通过。
- 真实 `swift`、`xcodebuild`、`xcodegen`、`swiftlint` 和 iOS Simulator：当前环境不可用，未伪造结果。

- CI 工作流增加 always 报告兜底：若 XcodeGen 或工程准备阶段失败，仍会生成真实失败原因并上传。

## 当前增量（可执行 Windows 静态门禁）

- 新增 `scripts/windows-static-check.ps1`，以 UTF-8 BOM 兼容 Windows PowerShell 5.1。
- 执行命令：`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/windows-static-check.ps1`。
- 结果：`WINDOWS_STATIC_GATE=PASS`；覆盖必需文件、Swift 禁用 API、括号、页面、免责声明、entitlements、LF 换行、Node 语法和 Bash 语法。
- 代码修复：儿童危象安全标记、Dashboard/History 个人资料分类、提醒持久化、后台重新锁定、持久化错误反馈、统一 CSV 导出器、PDF 长备注换行、HealthKit 授权文案和 Web 原型外部字体移除。

## 2026-09-11 继续执行后的复核

- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/windows-static-check.ps1`：通过，输出 `WINDOWS_STATIC_GATE=PASS`。
- `C:\Program Files\Git\bin\bash.exe -n scripts/remote-verify.sh`：通过。
- `node --check app.js`：通过。
- entitlements XML 解析：通过；Swift 13 个文件括号计数一致，未发现 `fatalError`、`try!` 或强制解包模式；文本文件 CRLF 扫描为 0。
- 代码修复：资料读取和记录模型查询增加错误反馈；删除失败回滚后重新按时间排序；架构文档明确 HealthKit 同步收缩压/舒张压及可选脉搏；CSV/PDF 用例标注为已编写、待 macOS 执行。
- 仍未执行：真实 Swift 编译、XCTest/UI Test、覆盖率、`xcodebuild analyze`、Instruments 性能、HealthKit/Face ID/通知权限验证；当前 Windows 环境不具备这些工具链。

## 2026-09-12 继续执行后的复核

- 修改：儿童本地筛查参考表、混合极端血压优先级、舒张压/脉搏统计、英文页面本地化、ReadingUseCase、提醒调度失败反馈、稳定的 App Store 生命周期、删除确认、趋势图 500 点采样、严格 UI 断言、HealthKit 可选脉搏同步、Face ID 不可用时自动回滚锁定开关、提醒时间重排失败自动回滚。
- 新增单元用例：混合极端读数 `89/200`、无出生日期年龄为空、注入 `now` 的未来时间边界、UTC CSV 排序、默认儿科参考、完整收缩压/舒张压/脉搏及晨晚统计字段。
- 静态执行：Windows 静态门禁通过；Git Bash `bash -n scripts/remote-verify.sh` 通过；Node 语法通过；Swift 花括号与禁用 API扫描通过；英文 strings 无重复 key。
- 便携语义烟测：`python scripts/portable-boundary-check.py` 输出 `PORTABLE_BOUNDARY_CHECK=PASS (12/12)`；该脚本只验证阈值表语义，不替代 Swift XCTest。
- 仍未执行：macOS/Xcode 真实编译、XCTest/UI Test、覆盖率、analyze、Instruments、真实通知/HealthKit/Face ID 权限验证。

## 2026-09-12 完成审计与 CI 稳定性复核

- 修改文件：`BPHealth/BPHealthApp.swift`、`BPHealth/Views/BPHealthViews.swift`、`BPHealth/Domain/Rules.swift`、`BPHealth/Models/BPHealthModels.swift`、`BPHealth/Services/PlatformServices.swift`、`BPHealth/Core/UseCases/ReadingUseCases.swift`、测试、英文资源、文档和 CI/静态检查脚本。
- 执行命令：`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/windows-static-check.ps1`、`bash -n scripts/remote-verify.sh`、`node --check app.js`、entitlements XML 解析、Swift 禁用 API/括号/换行扫描、Localizable.strings 语法扫描。
- 结果：全部可执行检查通过；便携边界语义 12/12 通过；CI 脚本新增 Simulator 显式启动、警告数和 XCTest 摘要记录。
- 环境失败原因：Windows 没有 Xcode、Swift、Simulator、XcodeGen 或 SwiftLint，无法获得真实 iOS 编译和运行时证据。
- 修复方案：macOS runner 继续通过 `.github/workflows/ios-ci.yml` 执行真实门禁；CI 失败时由 `CI_REPORT.md` 和 artifacts 提供可追踪日志。

## 2026-09-12 最终增量（HealthKit 导入稳定性）

- 修改：`BPHealth/Views/BPHealthViews.swift`。
- 修复：HealthKit 导入现在按“时间戳 + 收缩压 + 舒张压”去重，跳过重复记录后再写入本地 SwiftData；保留脉搏、空腹和备注；导入失败继续保留本地数据。
- 执行：`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/windows-static-check.ps1`、`C:\Program Files\Git\bin\bash.exe -n scripts/remote-verify.sh`、`node --check app.js`、`python scripts/portable-boundary-check.py`。
- 结果：Windows 静态门禁通过；Bash、Node 语法通过；便携边界语义检查 12/12 通过。
- 仍待 macOS：Swift 编译、XCTest/UI Test、覆盖率、`xcodebuild analyze`、HealthKit/通知/Face ID 真机权限验证。

## 2026-09-12 质量门禁增强

- 修改：`scripts/windows-static-check.ps1`。
- 增强：静态门禁现在显式扫描 Swift 强制解包（含 `as!`），同时保留 `try!`、`fatalError` 检查；当前 14 个 Swift 文件均通过。
- 验证：Windows 静态门禁仍输出 `WINDOWS_STATIC_GATE=PASS`，便携边界检查仍为 12/12。

## 2026-09-12 本地化增量

- 修改：`BPHealth/Resources/en.lproj/Localizable.strings`。
- 补充：解锁遮罩、导出提示、隐私存储说明、未来时间警告、输入错误、PDF/加密备份失败和本地持久化错误等英文文案；英文资源共 147 个 key，无重复 key。
- 安全文案仍保留要求的中文免责声明原文，避免英文环境丢失医疗安全提示。

## 2026-09-12 危象动作安全文案

- 修改：`BPHealth/Domain/Rules.swift`、`BPHealth/Models/BPHealthModels.swift`。
- 修复：成人高血压危象结果现在明确要求立即复测并联系急诊或医生评估；英文动作同步增强，`isUrgent` 与可见建议一致。
- 验证：现有危象边界、混合极端读数和英文显示测试仍由 macOS XCTest 门禁执行；Windows 静态门禁已通过。

## 儿科规则参考说明

- 架构文档已补充中国高血压健康管理规范来源。规范建议 3–17 岁采用年龄、性别和身高百分位表格标准，简化公式仅用于初筛；本工程因此把内置表标为筛查参考，并在资料不完整或无匹配表时要求儿科医生评估。

## 2026-09-12 趋势统计修复

- 修改：`BPHealth/Views/BPHealthViews.swift`。
- 修复：趋势页的平均值、晨间/晚间值和脉搏统计现在使用当前 7/30/90 天或全部时间筛选后的记录，与图表和极值卡片保持一致。
- 验证：Windows 静态门禁、Bash 语法和 Node 语法通过；时间范围交互仍需 macOS UI Test 执行。

## 2026-09-12 加密密钥竞态修复

- 修改：`BPHealth/Services/LocalEncryptionService.swift`。
- 修复：Keychain 首次写入遇到 `errSecDuplicateItem` 时重新读取已有 AES-256 密钥，避免并发导出返回错误密钥导致备份无法解密。
- 验证：源码静态门禁通过；CryptoKit/Security 往返测试仍需 macOS/iOS XCTest 执行。

## 2026-09-12 英文 CSV 导出

- 修改：`BPHealth/Data/Persistence.swift`、`BPHealth/Views/BPHealthViews.swift`、`BPHealthTests/BPHealthRuleTests.swift`。
- 功能：CSV 导出器新增语言参数；英文模式输出英文表头、Yes/No、手臂、体位和情绪值，中文默认行为保持不变。
- 测试：新增英文表头和布尔值单元用例，待 macOS XCTest 执行。

## 2026-09-12 资料年龄入口

- 修改：`BPHealth/Views/BPHealthViews.swift`、`BPHealthTests/BPHealthUITests.swift`、英文资源。
- 功能：资料页新增可选年龄输入；输入年龄会清除出生日期，启用出生日期会清除年龄覆盖值；两者都会持久化并参与儿科/成人规则判断。
- UI 用例新增年龄字段可见性断言，待 macOS Simulator 执行。

## 2026-09-12 Dashboard MVVM 接入

- 修改：`BPHealth/Views/BPHealthViews.swift`、`BPHealth/Core/ViewModels/DashboardViewModel.swift`。
- 改进：仪表盘统计改由 `DashboardViewModel` 计算，记录和资料变化时刷新，并显式注入当前规则引擎；避免 View 直接承担统计业务逻辑。
- 验证：静态门禁、Bash 和 Node 语法通过；ViewModel/XCTest 运行仍需 macOS。

## 2026-09-12 成人性别阈值回归用例

- 新增单元用例：验证成年男性和女性在相同 140/90 读数下均为 1 级高血压，同时保留性别风险说明文案。
- 该用例用于防止性别信息意外改变成人诊断阈值；待 macOS XCTest 执行。

## 2026-09-12 趋势采样性能门禁

- 修改：`BPHealth/Core/ViewModels/DashboardViewModel.swift`、`BPHealth/Views/BPHealthViews.swift`、`BPHealthTests/BPHealthRuleTests.swift`。
- 改进：抽出 `TrendSampler`，对 10,000 条数据生成最多 500 个图表索引，统计仍使用完整记录；新增 10,000 点采样边界用例。
- 验证：Windows 静态门禁通过；真实滚动帧率和 Charts 性能仍需 Simulator/Instruments。

## 2026-09-12 英文 PDF 导出

- 修改：`BPHealth/Core/UseCases/ExportUseCases.swift`、`BPHealth/Views/BPHealthViews.swift`、`BPHealthTests/BPHealthRuleTests.swift`。
- 功能：PDF 导出新增语言参数，英文模式翻译标题、空腹、手臂、体位、情绪、运动、服药和备注标签；医疗免责声明仍保留规定的中文原文。
- 测试：新增英文 PDF 生成用例，待 macOS/UIKit XCTest 执行。

## 2026-09-12 本地优先同步边界

- 新增：`BPHealth/Core/Sync/ReadingSyncService.swift`，定义可替换的 `ReadingSyncService` 和默认 `LocalOnlySyncService`。
- 行为：默认同步实现不联网、不上传，只返回空结果；未来可注入 iCloud/CloudKit 适配器。
- 测试：新增本地空同步异步单元用例，待 macOS XCTest 执行。

## 2026-09-12 本地数据删除控制

- 修改：`BPHealth/Data/Persistence.swift`、`BPHealth/Core/UseCases/ReadingUseCases.swift`、`BPHealth/Views/BPHealthViews.swift`、测试和英文资源。
- 功能：设置页新增“删除全部本地数据”确认流程；批量清除经 UseCase/Repository 原子删除血压记录和用户资料，失败时恢复内存列表与资料并显示持久化错误。
- 测试：新增 Repository 全量清除、资料删除和设置页入口断言；真实 SwiftData/UI 测试待 macOS 执行。

## 2026-09-12 最终复核（当前环境）

- 执行命令：`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/windows-static-check.ps1`、`C:\Program Files\Git\bin\bash.exe -n scripts/remote-verify.sh`、`node --check app.js`、Swift 禁用 API/强制解包扫描。
- 结果：`WINDOWS_STATIC_GATE=PASS`、`PORTABLE_BOUNDARY_CHECK=PASS (12/12)`、Bash 语法通过、Node 语法通过、`SWIFT_FORBIDDEN_SCAN=PASS`。
- 关键代码复核：本地数据清除通过 `ReadingUseCase -> ReadingRepository.clearAllLocalData()` 同一 SwiftData context 一次保存，同时删除记录和用户资料；默认 `LocalOnlySyncService` 不联网且可替换为未来 iCloud/CloudKit 适配器。
- 未执行且不可在当前 Windows 环境伪造：XcodeGen、Swift 编译、XCTest/UI Test、`xcodebuild analyze`、覆盖率、Simulator/Instruments、真实通知/HealthKit/Face ID 权限验证。应由 `.github/workflows/ios-ci.yml` 在 macOS runner 提供最终证据。
## 2026-09-12 隐私清单增量

- 新增：`BPHealth/PrivacyInfo.xcprivacy`，声明不跟踪、不收集个人数据，并记录 UserDefaults 本地设置访问理由。
- 文档：README 与架构文档补充隐私清单及 App Store Connect 复核边界。
- 验证：XML/plist 结构和必需隐私声明由 Windows 静态门禁检查；真实 App Store Connect 问卷与签名产物仍需 macOS/开发者账号环境复核。

## 2026-09-12 继续质量修复

- 修复 ACC/AHA 规则：仅中国指南使用 3 级分支，ACC/AHA 的 180/110 归入 stage 2；新增指南切换边界测试。
- 修复趋势图：采样强制包含首尾点，Y 轴根据当前数据动态扩展，避免 220 以上收缩压或高脉搏被裁切；无脉搏时显示“—”。
- 修复导入计数：HealthKit 导入按时间 ±1 秒及血压值去重，持久化失败不计入导入成功数。
- 本地数据清除同时移除提醒、指南、HealthKit 开关、语言和锁定设置，并取消本地提醒；HealthKit 外部数据不主动删除。
- 日常建议改为 AdviceItem，补充“非诊断，仅供参考”提示；增加读取行 accessibility identifier，降低 UI 测试对本地化文本的依赖。
- 新增隐私清单、可覆盖 Bundle Identifier 的 `Config/Shared.xcconfig`，并在 XcodeGen/SwiftPM 配置中显式处理资源边界。
- 当前 Windows 静态门禁仍需在上述修改后重跑；真实 macOS 编译、UI 测试、覆盖率和权限验证仍未执行。

## 2026-09-12 末轮静态门禁

- 执行：`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/windows-static-check.ps1`、`C:\Program Files\Git\bin\bash.exe -n scripts/remote-verify.sh`、`node --check app.js`、`python scripts/portable-boundary-check.py`。
- 结果：`WINDOWS_STATIC_GATE=PASS`、Bash 语法通过、Node 语法通过、`PORTABLE_BOUNDARY_CHECK=PASS (12/12)`。
- 新增检查：隐私清单 XML、显式 XcodeGen 资源、可配置 Bundle Identifier、SwiftPM 排除 App 隐私清单、Swift 禁用 API/强制解包和文本换行。
- 真实 macOS 证据仍缺失：XcodeGen 生成、xcodebuild build/test/analyze、XCTest/UI Test、xccov、Simulator 截图和真机权限测试。

## 2026-09-12 本轮回归结果

- Windows 静态门禁：通过；便携边界：12/12；Bash 与 Node 语法：通过；文本卫生：通过。
- 新增/修复后的测试资产：年龄 17/18 分界、ACC/AHA 180/110 映射、特殊资料 round-trip（Xcode App target）、日常建议英译与免责声明、10,000 条列表投影/趋势采样性能基准、趋势采样首尾点。
- 这些 XCTest 与真实 SwiftData/UI/Charts 性能结果仍需 macOS Xcode runner 执行并回填；当前报告不把静态结果等同于完整 DoD。

## 2026-09-12 日期、英文与性能测试资产补充

- `UserProfile.age(asOf:calendar:)` 和 `DashboardStats(calendar:)` 支持固定 UTC 日历测试，新增生日 17/18 岁及晨晚统计用例。
- 英文模式补充动态分类安全提示、手臂/体位/情绪、BMI、HealthKit/提醒状态和日常建议文案；日常建议均携带非诊断提示。
- 新增 10,000 条列表投影与趋势采样性能基准；真实 SwiftUI 滚动帧率仍需 Instruments。

## 2026-09-12 UI 与配置门禁补充

- UI 测试移除可跳过核心导航的 `if exists` 分支，记录行使用稳定 accessibility identifier，并精确检查医疗免责声明。
- XcodeGen 资源显式包含本地化目录和 PrivacyInfo，远程脚本从构建产物安装并启动 App 后再截图，且动态读取可配置 Bundle Identifier。
- 当前本机仍只能验证脚本和源码静态门禁；上述 UI 运行时行为需要 macOS Simulator 证据。

## 2026-09-12 UI 用例强化

- 新增实际空腹开关切换断言和趋势 30 天范围切换断言。
- 新增隐私页精确免责声明断言；记录行采用 accessibility identifier，避免按动态本地化文本定位。
- 由于没有 iOS Simulator，本轮仅完成源码与脚本门禁，未把这些 UI 用例标记为已运行通过。

## 2026-09-12 继续回归（当前工作树）

- 命令：`scripts/windows-static-check.ps1`、`bash -n scripts/remote-verify.sh`、`node --check app.js`、`python scripts/portable-boundary-check.py`。
- 结果：静态门禁通过、Bash/Node 语法通过、边界语义 12/12；未发现业务 Swift 强制解包、`try!` 或 `fatalError`。
- 仍待外部环境：macOS XcodeGen/build/test/analyze、XCTest/UI Test 实际运行、覆盖率、Simulator 截图、Instruments、HealthKit/通知/Face ID 真机验证。

## 2026-09-12 平台服务依赖注入

- 新增 `NotificationServicing`、`AuthenticationServicing`、`HealthKitServicing` 协议，AppContainer 可注入拒绝/不可用 mock。
- 新增平台失败路径测试资产：通知授权/调度失败、生物识别拒绝、HealthKit 授权/读取/写入失败均应保持本地流程不崩溃。
- Windows 静态门禁通过；协议调用与 XCTest 结果仍需 macOS Xcode 实际编译执行。

## 2026-09-12 平台协议注入回归

- 修改：`PlatformServices.swift`、`AppContainer.swift`、`BPHealthRuleTests.swift`。
- 验证资产：注入通知拒绝、生物识别拒绝、HealthKit 不可用/读取空结果/写入失败 mock，确保 UI 依赖可以在不崩溃的情况下回退本地流程。
- 当前执行：Windows 静态门禁通过；协议一致性、UIKit/HealthKit 编译和 XCTest 仍需 macOS。

## 2026-09-12 协议注入静态回归

- 复核 `@MainActor` 平台协议、`any` 服务依赖、SwiftPM 条件测试和 mock 实现；未发现静态结构冲突。
- 执行 Windows 静态门禁、Bash/Node 语法检查，全部通过；真实 Swift 5.9 编译仍需 macOS。

## 2026-09-12 XCTest 异步断言编译修复

- 修复 `testInjectedPlatformFailuresAreHandledWithoutCrashing`：先在异步测试上下文取得平台服务结果，再传给同步 `XCTAssertFalse`，避免 `async call in an autoclosure` 编译错误。
- 复核其余测试未在 XCTest 断言 autoclosure 中直接使用 `await`。
- Windows 静态门禁：`WINDOWS_STATIC_GATE=PASS`、`PORTABLE_BOUNDARY_CHECK=PASS (12/12)`。

## 2026-09-12 儿科紧急建议安全修复

- 修复：`DietaryAdviceRuleEngine` 现在保留儿科读数的 `isUrgent` 标记；儿童/青少年超过 180/120 mmHg 时先展示复测、急诊或儿科医生联系提示，再附加个体化饮食建议。
- 增强：中国指南 3 级高血压建议先提示尽快联系医生，肾病仍会抑制富钾建议；所有新增建议继续携带“非诊断，仅供参考”。
- 新增测试资产：`testPediatricUrgentClassificationKeepsUrgentAdvice`，覆盖儿童危急读数、紧急动作和免责声明。
- 验证：Windows 静态门禁、Bash/Node 语法、便携边界检查通过；真实 Swift/XCTest 运行仍需 macOS Xcode runner。

## 2026-09-12 最终 Windows 交付门禁

- 必需交付物：16/16 存在；Swift 禁用 API扫描通过；`WINDOWS_STATIC_GATE=PASS`。
- 脚本与边界：`PORTABLE_BOUNDARY_CHECK=PASS (12/12)`、`BASH_SYNTAX=PASS`、`NODE_SYNTAX=PASS`。
- 环境证据：本机 `xcodebuild`、XcodeGen、Swift、SwiftLint、Simulator 和 Instruments 均不可用，且未配置 GitHub 认证或远程 Mac；因此未伪造编译、XCTest、UI、覆盖率、分析、截图或真机权限结果。
- 交付结论：源码、工程描述、CI 工作流、测试资产和文档已完成；完整 DoD 的 macOS 证据需在 CI/远程 Mac 首次运行后回填 `CI_REPORT.md` 与本报告。

## 2026-09-12 CI 证据链修复

- 修改：新增 `scripts/ci_report.py`，从本轮 `.xcresult`/`xccov` 读取测试数量与覆盖率；缺失结果包、规则文件覆盖率、警告或截图时门禁失败，不再默认通过。
- 修改：`scripts/remote-verify.sh` 只允许真实 macOS 执行，使用独立 DerivedData 和工件目录，避免复用旧 App 或旧报告；本轮报告同步到 `artifacts/CI_REPORT.md`。
- 修改：GitHub Actions 覆盖所有分支 push、PR 和手动触发；SwiftLint 使用 strict，准备阶段失败、报告缺失和工件上传失败都会使工作流失败。
- 静态验证：Windows 静态门禁、Python/Bash 语法、便携边界检查通过；未执行 macOS CI。
- 提交限制：工作区 `.git` 目录对当前沙箱只读，`git add/commit` 返回 `Permission denied`；没有推送或伪造提交。

## 2026-09-12 Swift UI 测试编译前审计

- 修复：`BPHealthUITests` 使用非可选 `XCUIApplication`，移除会导致“对非可选值做条件绑定”的旧 `guard let app`。
- 修复：`AppContainer`、`BPUIStore`、`BPHealthRootView` 避免在默认参数中直接实例化 `@MainActor` 类型；服务依赖在主 actor 初始化体内创建。
- 验证：Windows 静态门禁、Python/Bash 语法和 Swift 禁用 API 扫描通过；实际 Swift/Xcode 编译仍必须由 macOS CI 证明。

## 2026-09-12 macOS CI 最终门禁

- 运行：[GitHub Actions 34670578007](https://github.com/hrqc/xueyajilu/actions/runs/34670578007)，提交 `544d98f6debf742061690d2972ed8996504a42cf`。
- 修改文件：`BPHealth/Views/BPHealthViews.swift`、`BPHealthTests/BPHealthRuleTests.swift`、`BPHealthTests/BPHealthUITests.swift`、`BPHealthTests/BPHealthViewCoverageTests.swift`、`project.yml`、`scripts/ci_report.py`、`scripts/remote-verify.sh`。
- 执行命令：macOS runner 上的 XcodeGen、`xcodebuild build`、`xcodebuild test -enableCodeCoverage YES`、`xcodebuild analyze`、SwiftLint strict、`xcrun simctl` 安装/启动/截图及 `xccov` 门禁。
- 结果：Build 通过；XCTest/UI Test `54/54` 通过；analyze 通过；SwiftLint 通过；编译/分析警告 `0`；App 安装、启动、截图均通过；整体覆盖率 `80.00%`；核心规则覆盖率 `93.71%`；最终质量门禁 PASS。
- 本轮修复：补充 SwiftUI 页面 body、空状态、英文状态和 BPUIStore 本地生命周期覆盖，修复 Profile 慢性病开关的稳定 accessibility identifier；未降低生产安全存储策略。

## 当前已知限制

- Face ID/Touch ID、HealthKit 权限与真实血压写入、通知权限和 VoiceOver/动态字体仍需真实设备或辅助技术复核；本轮是 macOS iPhone Simulator 验证。
- GitHub Actions 使用无签名模拟器构建；加密备份在无 Keychain entitlement 的测试进程中按平台错误路径安全跳过，生产实现仍使用 Keychain + AES-GCM。
- SwiftData 迁移、iCloud 同步和 App Store Connect 隐私问卷需在正式签名工程中复核。
