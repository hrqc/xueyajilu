import Foundation
import SwiftData

public enum BPArm: String, Codable, CaseIterable, Sendable, Hashable { case left = "左臂"; case right = "右臂" }
public enum BodyPosition: String, Codable, CaseIterable, Sendable, Hashable { case sitting = "坐位"; case standing = "站立"; case lying = "卧位" }
public enum Mood: String, Codable, CaseIterable, Sendable, Hashable { case calm = "平静"; case stressed = "紧张"; case tired = "疲劳"; case unwell = "不适" }
public enum BPGuideline: String, Codable, CaseIterable, Sendable, Hashable { case china = "中国指南"; case accAha = "ACC/AHA" }

public extension BPArm {
    func displayName(language: AppLanguage) -> String { language == .english ? (self == .left ? "Left arm" : "Right arm") : rawValue }
}
public extension BodyPosition {
    func displayName(language: AppLanguage) -> String { language == .english ? (self == .sitting ? "Sitting" : self == .standing ? "Standing" : "Lying") : rawValue }
}
public extension Mood {
    func displayName(language: AppLanguage) -> String {
        guard language == .english else { return rawValue }
        switch self {
        case .calm: return "Calm"
        case .stressed: return "Stressed"
        case .tired: return "Tired"
        case .unwell: return "Unwell"
        }
    }
}

@Model public final class BloodPressureReading {
    @Attribute(.unique) public var id: UUID
    public var measuredAt: Date
    public var systolic: Int
    public var diastolic: Int
    public var pulse: Int?
    public var note: String
    public var armRaw: String?
    public var positionRaw: String?
    public var moodRaw: String?
    public var exerciseBefore: Bool
    public var medicationTaken: Bool
    public var fasting: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), measuredAt: Date = .now, systolic: Int, diastolic: Int,
                pulse: Int? = nil, note: String = "", arm: BPArm? = nil,
                position: BodyPosition? = nil, mood: Mood? = nil,
                exerciseBefore: Bool = false, medicationTaken: Bool = false,
                fasting: Bool = false) {
        self.id = id; self.measuredAt = measuredAt; self.systolic = systolic; self.diastolic = diastolic
        self.pulse = pulse; self.note = note; self.armRaw = arm?.rawValue; self.positionRaw = position?.rawValue
        self.moodRaw = mood?.rawValue; self.exerciseBefore = exerciseBefore; self.medicationTaken = medicationTaken
        self.fasting = fasting; self.createdAt = .now; self.updatedAt = .now
    }
    public var arm: BPArm? { get { armRaw.flatMap(BPArm.init(rawValue:)) } set { armRaw = newValue?.rawValue } }
    public var position: BodyPosition? { get { positionRaw.flatMap(BodyPosition.init(rawValue:)) } set { positionRaw = newValue?.rawValue } }
    public var mood: Mood? { get { moodRaw.flatMap(Mood.init(rawValue:)) } set { moodRaw = newValue?.rawValue } }
}

@Model public final class UserProfile {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var birthDate: Date?
    public var ageOverride: Int?
    public var sex: String
    public var heightCm: Double?
    public var weightKg: Double?
    public var pregnant: Bool
    public var kidneyDisease: Bool
    public var diabetes: Bool
    public var heartDisease: Bool
    public var otherChronicConditions: String
    public var currentMedication: String
    public var targetSystolicMin: Int
    public var targetSystolicMax: Int
    public var targetDiastolicMin: Int
    public var targetDiastolicMax: Int

    public init(id: UUID = UUID(), name: String = "", birthDate: Date? = nil, ageOverride: Int? = nil, sex: String = "未说明",
                heightCm: Double? = nil, weightKg: Double? = nil, pregnant: Bool = false,
                kidneyDisease: Bool = false, diabetes: Bool = false, heartDisease: Bool = false,
                otherChronicConditions: String = "", currentMedication: String = "",
                targetSystolicMin: Int = 90, targetSystolicMax: Int = 140,
                targetDiastolicMin: Int = 60, targetDiastolicMax: Int = 90) {
        self.id=id; self.name=name; self.birthDate=birthDate; self.ageOverride=ageOverride; self.sex=sex; self.heightCm=heightCm; self.weightKg=weightKg
        self.pregnant=pregnant; self.kidneyDisease=kidneyDisease; self.diabetes=diabetes; self.heartDisease=heartDisease
        self.otherChronicConditions=otherChronicConditions; self.currentMedication=currentMedication
        self.targetSystolicMin=targetSystolicMin; self.targetSystolicMax=targetSystolicMax; self.targetDiastolicMin=targetDiastolicMin; self.targetDiastolicMax=targetDiastolicMax
    }
    public var age: Int? {
        age(asOf: .now, calendar: .current)
    }
    public func age(asOf date: Date, calendar: Calendar = .current) -> Int? {
        if let ageOverride, ageOverride >= 0 { return ageOverride }
        guard let birthDate else { return nil }
        let computed = calendar.dateComponents([.year], from: birthDate, to: date).year
        return computed.flatMap { $0 >= 0 ? $0 : nil }
    }
    public var bmi: Double? {
        guard let heightCm, let weightKg, heightCm > 0, weightKg > 0 else { return nil }
        let meters = heightCm / 100
        return weightKg / (meters * meters)
    }
}

public struct ReadingDraft: Sendable {
    public var measuredAt: Date = .now; public var systolic: String = ""; public var diastolic: String = ""; public var pulse: String = ""
    public var note = ""; public var arm: BPArm?; public var position: BodyPosition?; public var mood: Mood?
    public var exerciseBefore = false; public var medicationTaken = false; public var fasting = false
    public init() {}
}

public enum ValidationIssue: Equatable, Sendable { case invalidSystolic; case invalidDiastolic; case systolicNotGreater; case invalidPulse; case futureDateWarning }
public struct ValidationResult: Sendable { public let issues: [ValidationIssue]; public var isValid: Bool { !issues.contains(where: { $0 != .futureDateWarning }) } }

public enum BPLevel: String, Codable, CaseIterable, Sendable, Hashable {
    case low = "低血压", normal = "正常", elevated = "正常高值", stage1 = "1级高血压", stage2 = "2级高血压", stage3 = "3级高血压", crisis = "高血压危象", pediatricEvaluation = "需儿科医生评估"
    public var colorName: String {
        switch self {
        case .low: "blue"
        case .normal: "green"
        case .elevated: "yellow"
        case .stage1: "orange"
        case .stage2: "red"
        case .stage3, .crisis: "purple"
        case .pediatricEvaluation: "gray"
        }
    }
}
public struct BPClassification: Sendable, Equatable {
    public let level: BPLevel; public let explanation: String; public let isUrgent: Bool; public let action: String
    public init(level: BPLevel, explanation: String, isUrgent: Bool, action: String) { self.level=level; self.explanation=explanation; self.isUrgent=isUrgent; self.action=action }
    public var colorName: String { level.colorName }
    public func displayLevel(language: AppLanguage) -> String {
        guard language == .english else { return level.rawValue }
        switch level {
        case .low: return "Low blood pressure"
        case .normal: return "Normal"
        case .elevated: return "Elevated"
        case .stage1: return "Stage 1 hypertension"
        case .stage2: return "Stage 2 hypertension"
        case .stage3: return "Stage 3 hypertension"
        case .crisis: return "Hypertensive crisis"
        case .pediatricEvaluation: return "Pediatric evaluation needed"
        }
    }
    public func displayExplanation(language: AppLanguage) -> String {
        guard language == .english else { return explanation }
        var result: String
        switch level {
        case .low: result = "Systolic pressure is below 90 or diastolic pressure is below 60 mmHg."
        case .normal: result = "The reading is below 120/80 mmHg."
        case .elevated: result = "Systolic pressure is 120–139 or diastolic pressure is 80–89 mmHg."
        case .stage1: result = "The reading is in the stage 1 reference range."
        case .stage2: result = "The reading is in the stage 2 reference range."
        case .stage3: result = "Systolic pressure is at least 180 or diastolic pressure is at least 110 mmHg."
        case .crisis: result = "The reading is above 180/120 mmHg and may indicate a hypertensive crisis."
        case .pediatricEvaluation: result = "Children and adolescents require age-, sex-, and height-based pediatric assessment."
        }
        if explanation.contains("成人分类阈值") { result += " Adult thresholds do not change by sex; discuss personal risk with a clinician." }
        if explanation.contains("老年人的血压目标") { result += " Older adults should individualize blood pressure targets with a clinician." }
        return result
    }
    public func displayAction(language: AppLanguage) -> String {
        guard language == .english else { return action }
        var result: String
        switch level {
        case .low: result = "Hydrate and watch for dizziness, fatigue, or fainting; seek care if symptoms occur."
        case .normal: result = "Maintain balanced habits and monitor regularly."
        case .elevated: result = "Reduce sodium, exercise regularly, and continue monitoring."
        case .stage1: result = "Monitor regularly and discuss a management plan with a clinician."
        case .stage2: result = "Repeat measurements and arrange a clinician review."
        case .stage3: result = "Contact a clinician promptly; seek urgent care if you feel unwell."
        case .crisis: result = "Repeat the measurement immediately and contact emergency services or a clinician; seek emergency care if you feel unwell."
        case .pediatricEvaluation: result = "Please ask a pediatric clinician to review the reading; do not self-diagnose."
        }
        if action.contains("老年人目标") { result += " Older adults should follow individualized clinical advice." }
        return result
    }
}

public struct AdviceItem: Identifiable, Sendable {
    public let id = UUID()
    public let text: String
    public let disclaimer: String = "非诊断，仅供参考"
    public init(text: String) { self.text = text }
    public var englishText: String {
        switch text {
        case "读数可能属于高血压危象，请立即复测并根据症状联系急诊；饮食建议不能替代紧急医疗评估。": return "This reading may indicate a hypertensive crisis. Repeat it now and seek emergency care based on symptoms; dietary advice cannot replace urgent medical assessment."
        case "儿童青少年读数达到紧急范围，请立即复测并联系急诊或儿科医生；饮食建议不能替代紧急医疗评估。": return "This pediatric reading is in an urgent range. Repeat it now and contact emergency or pediatric care; dietary advice cannot replace urgent medical assessment."
        case "读数达到较高范围，请尽快联系医生评估；饮食建议不能替代医疗评估。": return "This reading is in a high range. Arrange prompt clinical review; dietary advice cannot replace medical assessment."
        case "参考 DASH 饮食，减少钠盐和酒精，多选蔬菜、全谷物与低脂蛋白。": return "Consider a DASH-style diet: reduce sodium and alcohol, and choose vegetables, whole grains, and lean protein."
        case "控制体重并保持规律、适度运动；不要自行停药或改药。": return "Manage weight and exercise regularly at a moderate pace; do not stop or change medication on your own."
        case "在医生允许范围内增加富含钾的蔬果。": return "Increase potassium-rich fruits and vegetables only if your clinician says it is appropriate."
        case "补充水分，在医生允许范围内适量增加盐分，少食多餐。": return "Hydrate, use a moderate amount of salt only if your clinician permits, and eat smaller meals more often."
        case "起身和改变体位时放慢速度，避免久站；如出现头晕、乏力、晕厥或持续不适，请及时就医。": return "Rise slowly, avoid standing for long periods, and seek care for dizziness, fatigue, fainting, or persistent discomfort."
        case "保持蔬菜、全谷物和优质蛋白的均衡组合。": return "Choose a balanced combination of vegetables, whole grains, and quality protein."
        case "规律运动、睡眠充足，并按计划复测。": return "Exercise regularly, sleep well, and repeat measurements as planned."
        case "儿童青少年饮食和血压请由儿科医生个体化评估。": return "A pediatric clinician should individualize diet and blood pressure guidance for children and adolescents."
        case "空腹测量前静坐 5 分钟，避免咖啡因、吸烟和饮酒。": return "Before a fasting measurement, rest for 5 minutes and avoid caffeine, smoking, and alcohol."
        case "孕期饮食与血压目标需由产科医生个体化指导。": return "Pregnancy diet and blood pressure targets require individualized obstetric guidance."
        case "合并糖尿病时关注碳水分配和血糖，按医生建议管理。": return "With diabetes, consider carbohydrate distribution and glucose management as advised by your clinician."
        case "合并心脏病时控制钠盐和饱和脂肪，并遵循心脏科医生建议。": return "With heart disease, limit sodium and saturated fat and follow your cardiologist's advice."
        case "成人血压阈值不因性别改变，风险与饮食目标请结合个人情况咨询医生。": return "Adult blood pressure thresholds do not change by sex; discuss personal risk and dietary goals with a clinician."
        case "如需控制体重，请采用循序渐进方式并结合医生建议。": return "If weight management is needed, make gradual changes with clinical guidance."
        case "老年人饮食、运动和血压目标需结合整体健康状况个体化调整。": return "Older adults should individualize diet, exercise, and blood pressure goals with their overall health in mind."
        case "测量前静坐 5 分钟，保持袖带与心脏同高": return "Rest for 5 minutes before measuring and keep the cuff at heart level."
        case "保持规律运动与充足睡眠": return "Exercise regularly and get enough sleep."
        default: return text
        }
    }
}

public let medicalDisclaimer = "本应用不能替代医生诊断，如有不适请及时就医。"
