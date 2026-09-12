import Foundation
import Combine

public enum TrendSampler {
    public static func indices(count: Int, maxPoints: Int = 500) -> [Int] {
        guard count > 0, maxPoints > 0 else { return [] }
        guard count > maxPoints else { return Array(0..<count) }
        guard maxPoints > 1 else { return [0] }
        let last = count - 1
        let denominator = Double(maxPoints - 1)
        return (0..<maxPoints).map { index in
            Int((Double(index) * Double(last) / denominator).rounded())
        }
    }
}

public struct DashboardStats: Equatable {
    public let averageSystolic: Double?
    public let averageDiastolic: Double?
    public let averagePulse: Double?
    public let highestSystolic: Int?
    public let lowestSystolic: Int?
    public let highestDiastolic: Int?
    public let lowestDiastolic: Int?
    public let highestPulse: Int?
    public let lowestPulse: Int?
    public let morningAverage: Double?
    public let eveningAverage: Double?
    public let morningDiastolicAverage: Double?
    public let eveningDiastolicAverage: Double?
    public let morningPulseAverage: Double?
    public let eveningPulseAverage: Double?
    public let targetRate: Double
    public init(readings: [BloodPressureReading], target: UserProfile? = nil, calendar: Calendar = .current) {
        let values = readings
        func average(_ numbers: [Int]) -> Double? {
            numbers.isEmpty ? nil : Double(numbers.reduce(0, +)) / Double(numbers.count)
        }
        averageSystolic = average(values.map(\.systolic))
        averageDiastolic = average(values.map(\.diastolic))
        averagePulse = average(values.compactMap(\.pulse))
        highestSystolic = values.map(\.systolic).max()
        lowestSystolic = values.map(\.systolic).min()
        highestDiastolic = values.map(\.diastolic).max()
        lowestDiastolic = values.map(\.diastolic).min()
        highestPulse = values.compactMap(\.pulse).max()
        lowestPulse = values.compactMap(\.pulse).min()
        let morningValues = values.filter { calendar.component(.hour, from: $0.measuredAt) < 12 }
        let eveningValues = values.filter { calendar.component(.hour, from: $0.measuredAt) >= 18 }
        morningAverage = average(morningValues.map(\.systolic))
        eveningAverage = average(eveningValues.map(\.systolic))
        morningDiastolicAverage = average(morningValues.map(\.diastolic))
        eveningDiastolicAverage = average(eveningValues.map(\.diastolic))
        morningPulseAverage = average(morningValues.compactMap(\.pulse))
        eveningPulseAverage = average(eveningValues.compactMap(\.pulse))
        guard let target, !values.isEmpty else { targetRate = 0; return }
        targetRate = Double(values.filter { $0.systolic >= target.targetSystolicMin && $0.systolic <= target.targetSystolicMax && $0.diastolic >= target.targetDiastolicMin && $0.diastolic <= target.targetDiastolicMax }.count) / Double(values.count)
    }
}

@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public private(set) var stats = DashboardStats(readings: [])
    @Published public private(set) var latestClassification: BPClassification?
    private let engine: BloodPressureRuleEngine
    public init(engine: BloodPressureRuleEngine = .init()) { self.engine = engine }
    public func refresh(readings: [BloodPressureReading], profile: UserProfile? = nil, engine: BloodPressureRuleEngine? = nil) {
        stats = DashboardStats(readings: readings, target: profile)
        let activeEngine = engine ?? self.engine
        latestClassification = readings.sorted { $0.measuredAt > $1.measuredAt }.first.map { activeEngine.classify(systolic: $0.systolic, diastolic: $0.diastolic, profile: profile) }
    }
}
