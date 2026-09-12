import Foundation

public struct ReadingValidator {
    public init() {}
    public func validate(systolic: Int, diastolic: Int, pulse: Int?, measuredAt: Date, now: Date = .now) -> ValidationResult {
        var issues: [ValidationIssue] = []
        if !(50...300).contains(systolic) { issues.append(.invalidSystolic) }
        if !(30...200).contains(diastolic) { issues.append(.invalidDiastolic) }
        if systolic <= diastolic { issues.append(.systolicNotGreater) }
        if let pulse, !(30...250).contains(pulse) { issues.append(.invalidPulse) }
        if measuredAt > now { issues.append(.futureDateWarning) }
        return ValidationResult(issues: issues)
    }
}


public struct PediatricPercentileThreshold: Sendable {
    public let age: Int
    public let sex: String
    public let heightCm: ClosedRange<Double>
    public let systolic90: Int
    public let systolic95: Int
    public let diastolic90: Int
    public let diastolic95: Int
    public init(age: Int, sex: String, heightCm: ClosedRange<Double>, systolic90: Int, systolic95: Int, diastolic90: Int, diastolic95: Int) {
        self.age = age; self.sex = sex; self.heightCm = heightCm; self.systolic90 = systolic90; self.systolic95 = systolic95; self.diastolic90 = diastolic90; self.diastolic95 = diastolic95
    }
}

public struct PediatricPercentileEvaluator: Sendable {
    public let thresholds: [PediatricPercentileThreshold]
    /// 依据中国 3–17 岁儿童青少年年龄、性别、身高参考标准整理的本地筛查参考值。
    /// 这些值只用于健康管理筛查，不能用于儿童诊断；业务方可注入经医疗审核的完整百分位表。
    public static let chinaReferenceThresholds: [PediatricPercentileThreshold] = {
        let male90 = [102, 104, 106, 108, 110, 112, 114, 116, 118, 120, 122, 124, 126, 128, 130]
        let male95 = [105, 107, 109, 111, 113, 115, 117, 119, 121, 123, 125, 127, 129, 131, 133, 135]
        let female90 = [101, 103, 105, 107, 109, 111, 113, 115, 117, 119, 121, 123, 125, 127, 129]
        let female95 = [104, 106, 108, 110, 112, 114, 116, 118, 120, 122, 124, 126, 128, 130, 132]
        let maleDBP90 = [63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77]
        let maleDBP95 = [66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80]
        let femaleDBP90 = [62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76]
        let femaleDBP95 = [65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79]
        var values: [PediatricPercentileThreshold] = []
        for age in 3...17 {
            let index = age - 3
            for entry in [("男", male90[index], male95[index], maleDBP90[index], maleDBP95[index]),
                          ("女", female90[index], female95[index], femaleDBP90[index], femaleDBP95[index])] {
                values.append(PediatricPercentileThreshold(age: age, sex: entry.0, heightCm: 0.0...119.99, systolic90: entry.1 - 4, systolic95: entry.2 - 4, diastolic90: entry.3 - 2, diastolic95: entry.4 - 2))
                values.append(PediatricPercentileThreshold(age: age, sex: entry.0, heightCm: 120.0...149.99, systolic90: entry.1, systolic95: entry.2, diastolic90: entry.3, diastolic95: entry.4))
                values.append(PediatricPercentileThreshold(age: age, sex: entry.0, heightCm: 150.0...240.0, systolic90: entry.1 + 4, systolic95: entry.2 + 4, diastolic90: entry.3 + 2, diastolic95: entry.4 + 2))
            }
        }
        return values
    }()
    public init(thresholds: [PediatricPercentileThreshold] = PediatricPercentileEvaluator.chinaReferenceThresholds) { self.thresholds = thresholds }
    public func evaluate(age: Int, sex: String, heightCm: Double, systolic: Int, diastolic: Int) -> BPClassification {
        guard let threshold = thresholds.first(where: { $0.age == age && ($0.sex == sex || $0.sex == "未说明") && $0.heightCm.contains(heightCm) }) else {
            return .init(level: .pediatricEvaluation, explanation: "儿童青少年需依据年龄、性别和身高百分位评估。", isUrgent: false, action: "当前缺少匹配的百分位表，请由儿科医生评估。")
        }
        if systolic >= threshold.systolic95 || diastolic >= threshold.diastolic95 {
            return .init(level: .pediatricEvaluation, explanation: "读数达到或超过儿科第 95 百分位参考线。", isUrgent: false, action: "请尽快由儿科医生复核，不要自行诊断。")
        }
        if systolic >= threshold.systolic90 || diastolic >= threshold.diastolic90 {
            return .init(level: .pediatricEvaluation, explanation: "读数处于儿科第 90–95 百分位参考区间。", isUrgent: false, action: "建议复测并咨询儿科医生。")
        }
        return .init(level: .pediatricEvaluation, explanation: "读数低于当前儿科第 90 百分位参考线。", isUrgent: false, action: "继续按规范测量并定期儿科随访。")
    }
}

public struct BloodPressureRuleEngine {
    public var standard: BPGuideline
    public var pediatricEvaluator: PediatricPercentileEvaluator
    public init(standard: BPGuideline = .china, pediatricEvaluator: PediatricPercentileEvaluator = .init()) { self.standard = standard; self.pediatricEvaluator = pediatricEvaluator }

    public func classify(systolic: Int, diastolic: Int, profile: UserProfile? = nil) -> BPClassification {
        if let profile, let age = profile.age, age < 18 {
            guard age >= 2 else {
                return BPClassification(level: .pediatricEvaluation, explanation: "2 岁以下儿童不适用成人血压分类阈值。", isUrgent: false, action: "请由儿科医生进行专业评估，不要自行诊断。")
            }
            guard let height = profile.heightCm, height > 0 else {
                return BPClassification(level: .pediatricEvaluation, explanation: "2–17 岁需要年龄、性别和身高百分位评估。", isUrgent: false, action: "请补充身高并由儿科医生评估，不要自行诊断。")
            }
            if systolic > 180 || diastolic > 120 {
                return BPClassification(level: .pediatricEvaluation, explanation: "儿童青少年读数超过 180/120 mmHg，且不能直接套用成人危象诊断。", isUrgent: true, action: "请立即复测并联系急诊或儿科医生，不要自行诊断。")
            }
            return pediatricEvaluator.evaluate(age: age, sex: profile.sex, heightCm: height, systolic: systolic, diastolic: diastolic)
        }
        let base: BPClassification
        if systolic > 180 || diastolic > 120 {
            base = .init(level: .crisis, explanation: "读数超过 180/120 mmHg，可能属于高血压危象。", isUrgent: true, action: "请立即复测并联系急诊或医生评估；如伴不适，立即就医。")
        } else if standard == .china && (systolic >= 180 || diastolic >= 110) {
            base = .init(level: .stage3, explanation: "收缩压达到 180 或舒张压达到 110 mmHg。", isUrgent: true, action: "尽快联系医生评估，出现不适时立即就医。")
        } else if systolic < 90 || diastolic < 60 {
            base = .init(level: .low, explanation: "收缩压低于 90 或舒张压低于 60 mmHg。", isUrgent: false, action: "补水并留意头晕、乏力或晕厥；有症状请及时就医。")
        } else if standard == .accAha {
            if systolic >= 140 || diastolic >= 90 { base = .init(level: .stage2, explanation: "ACC/AHA：收缩压 ≥140 或舒张压 ≥90 mmHg。", isUrgent: false, action: "预约医生评估并持续监测。") }
            else if systolic >= 130 || diastolic >= 80 { base = .init(level: .stage1, explanation: "ACC/AHA：收缩压 130–139 或舒张压 80–89 mmHg。", isUrgent: false, action: "改善生活方式并与医生讨论风险。") }
            else if systolic >= 120 && diastolic < 80 { base = .init(level: .elevated, explanation: "ACC/AHA：收缩压 120–129 且舒张压低于 80 mmHg。", isUrgent: false, action: "减少盐分并继续监测。") }
            else { base = .init(level: .normal, explanation: "ACC/AHA：收缩压低于 120 且舒张压低于 80 mmHg。", isUrgent: false, action: "保持均衡生活方式并定期监测。") }
        } else if systolic >= 160 || diastolic >= 100 {
            base = .init(level: .stage2, explanation: "收缩压 160–179 或舒张压 100–109 mmHg。", isUrgent: false, action: "连续测量并预约医生评估。")
        } else if systolic >= 140 || diastolic >= 90 {
            base = .init(level: .stage1, explanation: "收缩压 140–159 或舒张压 90–99 mmHg。", isUrgent: false, action: "保持规律监测，和医生讨论管理方案。")
        } else if systolic >= 120 || diastolic >= 80 {
            base = .init(level: .elevated, explanation: "收缩压 120–139 或舒张压 80–89 mmHg。", isUrgent: false, action: "减少盐分、规律运动并继续监测。")
        } else {
            base = .init(level: .normal, explanation: "收缩压低于 120 且舒张压低于 80 mmHg。", isUrgent: false, action: "保持均衡生活方式并定期监测。")
        }
        var explanation = base.explanation
        var action = base.action
        if let profile, let age = profile.age, age >= 18, profile.sex != "未说明" {
            explanation += " 成人分类阈值不因性别改变，风险说明需结合个人情况。"
        }
        if let age = profile?.age, age >= 65 {
            explanation += " 老年人的血压目标需个体化，遵医嘱。"
            action += " 老年人目标请遵医嘱。"
        }
        return BPClassification(level: base.level, explanation: explanation, isUrgent: base.isUrgent, action: action)
    }
}

public struct DietaryAdviceRuleEngine {
    private let engine: BloodPressureRuleEngine
    public init(engine: BloodPressureRuleEngine = .init()) { self.engine = engine }
    public func advice(for reading: BloodPressureReading, profile: UserProfile? = nil) -> [AdviceItem] {
        let classification = engine.classify(systolic: reading.systolic, diastolic: reading.diastolic, profile: profile)
        let level = classification.level
        var result: [AdviceItem]
        if level == .crisis {
            result = [.init(text: "读数可能属于高血压危象，请立即复测并根据症状联系急诊；饮食建议不能替代紧急医疗评估。")]
        } else if level == .pediatricEvaluation && classification.isUrgent {
            result = [.init(text: "儿童青少年读数达到紧急范围，请立即复测并联系急诊或儿科医生；饮食建议不能替代紧急医疗评估。")]
        } else if level == .stage3 {
            result = [.init(text: "读数达到较高范围，请尽快联系医生评估；饮食建议不能替代医疗评估。")]
            result.append(contentsOf: ["参考 DASH 饮食，减少钠盐和酒精，多选蔬菜、全谷物与低脂蛋白。", "控制体重并保持规律、适度运动；不要自行停药或改药。"].map(AdviceItem.init(text:)))
            if profile?.kidneyDisease != true { result.append(.init(text: "在医生允许范围内增加富含钾的蔬果。")) }
        } else {
            switch level {
            case .crisis:
                result = [.init(text: "读数可能属于高血压危象，请立即复测并根据症状联系急诊；饮食建议不能替代紧急医疗评估。")]
            case .stage1, .stage2:
                result = ["参考 DASH 饮食，减少钠盐和酒精，多选蔬菜、全谷物与低脂蛋白。", "控制体重并保持规律、适度运动；不要自行停药或改药。"].map(AdviceItem.init(text:))
                if profile?.kidneyDisease != true { result.append(.init(text: "在医生允许范围内增加富含钾的蔬果。")) }
            case .low:
                result = ["补充水分，在医生允许范围内适量增加盐分，少食多餐。", "起身和改变体位时放慢速度，避免久站；如出现头晕、乏力、晕厥或持续不适，请及时就医。"].map(AdviceItem.init(text:))
            case .normal, .elevated:
                result = ["保持蔬菜、全谷物和优质蛋白的均衡组合。", "规律运动、睡眠充足，并按计划复测。"].map(AdviceItem.init(text:))
            case .pediatricEvaluation:
                result = [.init(text: "儿童青少年饮食和血压请由儿科医生个体化评估。")]
            case .stage3:
                result = []
            }
        }
        if reading.fasting { result.append(.init(text: "空腹测量前静坐 5 分钟，避免咖啡因、吸烟和饮酒。")) }
        if profile?.pregnant == true { result.append(.init(text: "孕期饮食与血压目标需由产科医生个体化指导。")) }
        if profile?.diabetes == true { result.append(.init(text: "合并糖尿病时关注碳水分配和血糖，按医生建议管理。")) }
        if profile?.heartDisease == true { result.append(.init(text: "合并心脏病时控制钠盐和饱和脂肪，并遵循心脏科医生建议。")) }
        if let sex = profile?.sex, !sex.isEmpty, sex != "未说明" { result.append(.init(text: "成人血压阈值不因性别改变，风险与饮食目标请结合个人情况咨询医生。")) }
        if let bmi = profile?.bmi, bmi >= 24 { result.append(.init(text: "如需控制体重，请采用循序渐进方式并结合医生建议。")) }
        if let age = profile?.age, age >= 65 { result.append(.init(text: "老年人饮食、运动和血压目标需结合整体健康状况个体化调整。")) }
        return result
    }
}
