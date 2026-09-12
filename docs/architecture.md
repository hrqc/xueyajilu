# 架构说明

BPHealth 采用 MVVM + Repository + UseCase + RuleEngine + Dependency Injection。SwiftUI 页面只依赖 `BPUIStore`/ViewModel，规则引擎不依赖 UI；SwiftData 模型通过 `ReadingRepository` 统一读写，`ReadingUseCase` 封装记录的查询、校验、增删改，便于未来替换 iCloud 或远端同步。`Models`、`Domain` 和规则/导出值对象保持可共享结构，SwiftData 用例与平台服务留在 iOS target，未来可由共享 target 复用规则到 watchOS；当前交付优先完成 iPhone iOS 17 App。`AppContainer` 统一持有 RuleEngine、DietaryAdviceRuleEngine 和平台服务；设置页切换指南时替换注入的引擎，Dashboard、History、Advice 共用同一规则配置。

`BloodPressureRuleEngine` 以 `BPGuideline` 配置为入口，按高血压危象、3 级高血压、低血压、2/1 级、正常高值、正常顺序判断；当收缩压偏低但舒张压同时达到高危阈值时优先提示高危，避免漏报。结果包含等级、颜色名、解释、紧急性和动作。儿童缺身高时只返回儿科评估提示，老年人、孕期和其他特殊人群通过 Profile 传入规则引擎，输出个体化风险和建议文案。

`ReadingSyncService` 是可替换的同步边界，默认注入 `LocalOnlySyncService`，不联网、不上传健康数据；未来可以在不改变 Repository/UseCase 的情况下接入经过用户授权的 iCloud/CloudKit 实现。

`DietaryAdviceRuleEngine` 只使用本地规则，依据分类、空腹和慢性病生成建议；危象等级优先给出紧急评估提示，肾病时不生成高钾建议。每条 `AdviceItem` 自带“非诊断，仅供参考”。

`NotificationService`、`AuthenticationService` 和 `HealthKitService` 是平台适配器。 它们分别通过 `NotificationServicing`、`AuthenticationServicing` 和 `HealthKitServicing` 协议注入，测试可以替换为拒绝/不可用 mock。权限拒绝或平台不可用时返回 false/空操作，UI 仍可使用本地记录。CSV 由 `CSVExporter` 生成；PDF 由 `PDFExporter` 使用 UIKit PDF renderer 生成，再由 ShareLink 分享。

HealthKit 写入默认关闭；用户在设置中启用后，新建/编辑的本地记录会尝试写入收缩压、舒张压和可选脉搏，失败不会阻断本地保存。备注、空腹、体位等扩展字段始终保留在本地记录中。导入 HealthKit 时关闭回写，避免重复同步。


UI 通过 `BPUIStore` 注入 SwiftData `ModelContext`、`ReadingUseCase` 和平台服务：启动时加载记录和资料，记录新增、编辑、删除先经 UseCase 校验，再由 Repository 写入本地容器，资料保存使用同一上下文。导出页使用健壮 CSV 转义和分页 PDF 生成；设置页接入提醒、Face ID/Touch ID 与 HealthKit 权限入口。HealthKit 相关查询在平台不可用或权限拒绝时返回空结果，不阻断本地记录。

设置页的“删除全部本地数据”通过 Repository/UseCase 原子清除血压记录和用户资料；失败时回滚 SwiftData 上下文并恢复界面状态。 同时重置本地提醒、指南、HealthKit 开关、语言和锁定设置，并取消本地通知；HealthKit 中的外部样本不会被删除。


`PediatricPercentileEvaluator` 接受可配置的年龄、性别、身高区间和第 90/95 百分位阈值，并内置中国 3–17 岁筛查参考表的本地版本（参考《中国 3～17 岁儿童青少年血压参照标准》及[中国高血压健康管理规范](https://csc.cma.org.cn/art/2020/5/8/art_619_34440.html)）。指南要求儿童采用年龄、性别和身高百分位表格标准，简化公式只能用于初筛；因此没有匹配表、年龄小于 3 岁或资料不完整时，只返回儿科医生评估提示，避免把成人阈值误用于儿童。当前内置表仍属于健康管理筛查参考，不能替代儿科诊断，正式发布前应由医疗审核替换或确认完整百分位数据。

`LocalEncryptionService` 使用 CryptoKit AES-GCM，并将 256 位密钥存入 Keychain（`WhenUnlockedThisDeviceOnly`）；不支持 CryptoKit/Security 的平台返回可处理错误。`EncryptedBackupExporter` 已接入导出页，用于生成可分享的加密备份；应用 entitlement 同时开启 `NSFileProtectionComplete`，由系统保护 SwiftData 数据库文件。

界面文案使用 SwiftUI `LocalizedStringKey` 与 `Localizable.strings`，根视图根据设置注入 `zh-Hans` 或 `en` locale；医疗免责声明和动态分类安全文案保留中文原文，避免语言切换时丢失安全信息。

当前 SwiftData Repository 仍使用系统数据保护存储；`EncryptedBackupExporter` 已将记录序列化后通过 `LocalEncryptionService` 生成 AES-GCM 加密备份。现有 SwiftData 主存储尚未逐条改为应用层 AES-GCM 字段，以避免在没有迁移方案时破坏既有数据。
隐私清单：`BPHealth/PrivacyInfo.xcprivacy` 声明默认不跟踪、不收集个人数据，并说明 UserDefaults 的本地设置访问理由；提交前仍需在 App Store Connect 复核实际权限和隐私问卷。
指南切换说明：危象规则保持跨指南一致（收缩压 >180 或舒张压 >120）；中国指南额外提供 3 级高血压，ACC/AHA 使用 stage 1/2 映射，因此 180/110 在 ACC/AHA 下归入 stage 2。
