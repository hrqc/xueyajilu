# BPHealth watchOS 预留

当前版本以 iPhone 为主，watchOS target 尚未创建。共享的 `BPHealthCore` Swift Package 可承载血压模型、规则引擎和导出 DTO；后续 watchOS App 只需增加轻量录入界面，并通过 HealthKit 与 iPhone 同步。任何 watchOS 页面仍需显示同一医疗免责声明。
