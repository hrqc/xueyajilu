import Foundation
import SwiftData

@MainActor
public final class ReadingRepository {
    private let context: ModelContext
    public init(context: ModelContext) { self.context = context }
    public func fetch(search: String = "", fasting: Bool? = nil) throws -> [BloodPressureReading] {
        let descriptor = FetchDescriptor<BloodPressureReading>(sortBy: [SortDescriptor(\.measuredAt, order: .reverse)])
        return try context.fetch(descriptor).filter { reading in
            (fasting == nil || reading.fasting == fasting) &&
            (search.isEmpty || reading.note.localizedCaseInsensitiveContains(search) || "\(reading.systolic)/\(reading.diastolic)".contains(search))
        }
    }
    public func save(_ reading: BloodPressureReading) throws { context.insert(reading); try context.save() }
    public func update(_ reading: BloodPressureReading) throws { reading.updatedAt = .now; try context.save() }
    public func delete(_ reading: BloodPressureReading) throws { context.delete(reading); try context.save() }
    public func deleteAll() throws {
        let readings = try fetch()
        readings.forEach { context.delete($0) }
        try context.save()
    }
    public func clearAllLocalData() throws {
        let readings = try fetch()
        let profiles = try context.fetch(FetchDescriptor<UserProfile>())
        readings.forEach { context.delete($0) }
        profiles.forEach { context.delete($0) }
        try context.save()
    }
    public func find(id: UUID) throws -> BloodPressureReading? {
        let targetID = id
        let descriptor = FetchDescriptor<BloodPressureReading>(predicate: #Predicate<BloodPressureReading> { reading in reading.id == targetID })
        return try context.fetch(descriptor).first
    }
}

public struct CSVExporter: Sendable {
    public init() {}
    public func export(_ readings: [BloodPressureReading], language: AppLanguage = .simplifiedChinese) -> String {
        let english = language == .english
        let yes = english ? "Yes" : "是"
        let no = english ? "No" : "否"
        func armName(_ arm: BPArm?) -> String {
            guard let arm else { return "" }
            if !english { return arm.rawValue }
            return arm == .left ? "Left" : "Right"
        }
        func positionName(_ position: BodyPosition?) -> String {
            guard let position else { return "" }
            if !english { return position.rawValue }
            switch position {
            case .sitting: return "Sitting"
            case .standing: return "Standing"
            case .lying: return "Lying"
            }
        }
        func moodName(_ mood: Mood?) -> String {
            guard let mood else { return "" }
            if !english { return mood.rawValue }
            switch mood {
            case .calm: return "Calm"
            case .stressed: return "Stressed"
            case .tired: return "Tired"
            case .unwell: return "Unwell"
            }
        }
        let rows = readings.sorted { $0.measuredAt < $1.measuredAt }.map { reading in
            let fields = [
                reading.measuredAt.ISO8601Format(),
                String(reading.systolic),
                String(reading.diastolic),
                reading.pulse.map(String.init) ?? "",
                reading.fasting ? yes : no,
                armName(reading.arm),
                positionName(reading.position),
                moodName(reading.mood),
                reading.exerciseBefore ? yes : no,
                reading.medicationTaken ? yes : no,
                reading.note
            ]
            return fields.map { field in
                "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
            }.joined(separator: ",")
        }
        let header = english ? "Measured at,Systolic,Diastolic,Pulse,Fasting,Arm,Position,Mood,Exercise before,Medication taken,Note" : "测量时间,收缩压,舒张压,脉搏,空腹,手臂,体位,情绪,测量前运动,已服药,备注"
        return ([header] + rows).joined(separator: "\n")
    }
}
