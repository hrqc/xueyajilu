import Foundation
import SwiftData

/// 血压记录用例层。UI 不需要知道 SwiftData 的保存细节，未来可替换为同步仓储。
@MainActor
public final class ReadingUseCase {
    private let repository: ReadingRepository

    public init(context: ModelContext) {
        repository = ReadingRepository(context: context)
    }

    public func list(search: String = "", fasting: Bool? = nil) throws -> [BloodPressureReading] {
        try repository.fetch(search: search, fasting: fasting)
    }

    public func create(_ reading: BloodPressureReading) throws {
        try validate(reading)
        try repository.save(reading)
    }

    public func update(_ reading: BloodPressureReading) throws {
        try validate(reading)
        try repository.update(reading)
    }

    public func delete(_ reading: BloodPressureReading) throws {
        try repository.delete(reading)
    }

    public func deleteAll() throws {
        try repository.deleteAll()
    }

    public func clearAllLocalData() throws {
        try repository.clearAllLocalData()
    }

    public func find(id: UUID) throws -> BloodPressureReading? {
        try repository.find(id: id)
    }

    private func validate(_ reading: BloodPressureReading) throws {
        let result = ReadingValidator().validate(systolic: reading.systolic, diastolic: reading.diastolic, pulse: reading.pulse, measuredAt: reading.measuredAt)
        if !result.isValid { throw ReadingUseCaseError.invalidInput(result.issues) }
    }
}

public enum ReadingUseCaseError: Error, Equatable, Sendable {
    case invalidInput([ValidationIssue])
}
