import Foundation
#if canImport(UIKit)
import UIKit
#endif

public struct ExportReading: Codable, Sendable {
    public let date: Date
    public let systolic: Int
    public let diastolic: Int
    public let pulse: Int?
    public let fasting: Bool
    public let note: String
    public let arm: BPArm?
    public let position: BodyPosition?
    public let mood: Mood?
    public let exerciseBefore: Bool
    public let medicationTaken: Bool
    public init(date: Date, systolic: Int, diastolic: Int, pulse: Int? = nil, fasting: Bool = false, note: String = "", arm: BPArm? = nil, position: BodyPosition? = nil, mood: Mood? = nil, exerciseBefore: Bool = false, medicationTaken: Bool = false) {
        self.date = date; self.systolic = systolic; self.diastolic = diastolic; self.pulse = pulse; self.fasting = fasting; self.note = note; self.arm = arm; self.position = position; self.mood = mood; self.exerciseBefore = exerciseBefore; self.medicationTaken = medicationTaken
    }
}

private struct BackupPayload: Codable {
    let generatedAt: Date
    let readings: [ExportReading]
}

/// 将记录序列化后用 Keychain 中的 AES-GCM 密钥加密，供本地备份或受控分享使用。
public struct EncryptedBackupExporter: Sendable {
    private let encryption: LocalEncryptionService
    public init(encryption: LocalEncryptionService = .init()) { self.encryption = encryption }
    public func export(readings: [ExportReading], generatedAt: Date = .now) throws -> Data {
        let payload = BackupPayload(generatedAt: generatedAt, readings: readings)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encryption.encrypt(encoder.encode(payload))
    }
    public func export(readings: [BloodPressureReading], generatedAt: Date = .now) throws -> Data {
        try export(readings: readings.map { ExportReading(date: $0.measuredAt, systolic: $0.systolic, diastolic: $0.diastolic, pulse: $0.pulse, fasting: $0.fasting, note: $0.note, arm: $0.arm, position: $0.position, mood: $0.mood, exerciseBefore: $0.exerciseBefore, medicationTaken: $0.medicationTaken) }, generatedAt: generatedAt)
    }
}

public struct PDFExporter: Sendable {
    public init() {}
    public func exportSummary(readings: [BloodPressureReading], title: String = "BPHealth 血压记录", language: AppLanguage = .simplifiedChinese) -> Data? {
        exportSummary(readings: readings.map { ExportReading(date: $0.measuredAt, systolic: $0.systolic, diastolic: $0.diastolic, pulse: $0.pulse, fasting: $0.fasting, note: $0.note, arm: $0.arm, position: $0.position, mood: $0.mood, exerciseBefore: $0.exerciseBefore, medicationTaken: $0.medicationTaken) }, title: title, language: language)
    }
    public func exportSummary(readings: [ExportReading], title: String = "BPHealth 血压记录", language: AppLanguage = .simplifiedChinese) -> Data? {
#if canImport(UIKit)
        let english = language == .english
        let titleText = english && title == "BPHealth 血压记录" ? "BPHealth blood pressure record" : title
        func armName(_ arm: BPArm?) -> String {
            guard let arm else { return "" }
            if !english { return arm.rawValue }
            return arm == .left ? "Left" : "Right"
        }
        func positionName(_ position: BodyPosition?) -> String {
            guard let position else { return "" }
            if !english { return position.rawValue }
            switch position { case .sitting: return "Sitting"; case .standing: return "Standing"; case .lying: return "Lying" }
        }
        func moodName(_ mood: Mood?) -> String {
            guard let mood else { return "" }
            if !english { return mood.rawValue }
            switch mood { case .calm: return "Calm"; case .stressed: return "Stressed"; case .tired: return "Tired"; case .unwell: return "Unwell" }
        }
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842), format: format)
        return renderer.pdfData { context in
            let lines = readings.sorted { $0.date < $1.date }.map { reading in
                let metadata = [
                    reading.fasting ? (english ? "Fasting" : "空腹") : (english ? "Not fasting" : "非空腹"),
                    armName(reading.arm),
                    positionName(reading.position),
                    moodName(reading.mood),
                    reading.exerciseBefore ? (english ? "Exercise before" : "测量前运动") : nil,
                    reading.medicationTaken ? (english ? "Medication taken" : "已服药") : nil,
                    reading.note.isEmpty ? nil : (english ? "Note: \(reading.note)" : "备注：\(reading.note)")
                ].compactMap { $0 }.joined(separator: " · ")
                let pulseLabel = english ? "Pulse" : "脉搏"
                return "\(reading.date.formatted())  \(reading.systolic)/\(reading.diastolic) mmHg  \(pulseLabel) \(reading.pulse.map(String.init) ?? "-")  \(metadata)"
            }
            let text = "\(titleText)\n\n\(lines.joined(separator: "\n"))\n\n\(medicalDisclaimer)"
            let font = UIFont.systemFont(ofSize: 12)
            let pageHeight: CGFloat = 760
            var y: CGFloat = 32
            context.beginPage()
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let characters = Array(String(line))
                let chunks: [String]
                if characters.isEmpty {
                    chunks = [""]
                } else {
                    chunks = stride(from: 0, to: characters.count, by: 48).map { start in
                        let end = min(start + 48, characters.count)
                        return String(characters[start..<end])
                    }
                }
                for chunk in chunks {
                    chunk.draw(at: CGPoint(x: 32, y: y), withAttributes: [.font: font])
                    y += 18
                    if y > pageHeight { context.beginPage(); y = 32 }
                }
            }
        }
        #else
        return nil
        #endif
    }
}
