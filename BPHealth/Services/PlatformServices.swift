import Foundation
import Combine
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif
#if canImport(HealthKit)
import HealthKit
#endif

@MainActor public protocol NotificationServicing {
    func requestAuthorization() async -> Bool
    func cancelDaily()
    func scheduleDaily(at date: Date) async -> Bool
}

@MainActor public protocol AuthenticationServicing {
    func authenticate(reason: String) async -> Bool
}

@MainActor public protocol HealthKitServicing {
    var isAvailable: Bool { get }
    func requestAuthorization() async throws -> Bool
    func readRecentReadings(since: Date) async throws -> [ExportReading]
    func save(_ reading: ExportReading) async throws
    func save(systolic: Int, diastolic: Int, pulse: Int?, measuredAt: Date) async throws
}

@MainActor public final class NotificationService: ObservableObject {
    public init() {}
    public func requestAuthorization() async -> Bool {
        #if canImport(UserNotifications)
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        #else
        return false
        #endif
    }
    public func cancelDaily() {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["bphealth.daily"])
        #endif
    }
    public func scheduleDaily(at date: Date) async -> Bool {
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        let english = UserDefaults.standard.string(forKey: "bphealth.language") == "en"
        content.title = english ? "BPHealth measurement reminder" : "BPHealth 测量提醒"
        content.body = english ? "Record today's blood pressure and keep track of your health trend." : "记录今天的血压，持续关注健康趋势。"
        let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.hour, .minute], from: date), repeats: true)
        let request = UNNotificationRequest(identifier: "bphealth.daily", content: content, trigger: trigger)
        return await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().add(request) { error in
                continuation.resume(returning: error == nil)
            }
        }
        #else
        return false
        #endif
    }
}

extension NotificationService: NotificationServicing {}

@MainActor public final class AuthenticationService {
    public init() {}
    public func authenticate(reason: String = "验证身份后查看健康记录") async -> Bool {
        #if canImport(LocalAuthentication)
        let context = LAContext(); var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
        #else
        return false
        #endif
    }
}

extension AuthenticationService: AuthenticationServicing {}

@MainActor public struct HealthKitService: @unchecked Sendable {
    #if canImport(HealthKit)
    private let store: HKHealthStore
    #endif
    public init() {
        #if canImport(HealthKit)
        store = HKHealthStore()
        #endif
    }
    public var isAvailable: Bool {
        #if canImport(HealthKit)
        return HKHealthStore.isHealthDataAvailable()
        #else
        return false
        #endif
    }
    public func requestAuthorization() async throws -> Bool {
        #if canImport(HealthKit)
        guard isAvailable, let systolic = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic), let diastolic = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic), let pulse = HKObjectType.quantityType(forIdentifier: .heartRate) else { return false }
        let shareTypes: Set<HKSampleType> = [systolic, diastolic, pulse]
        let readTypes: Set<HKObjectType> = [systolic, diastolic, pulse]
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
        return true
        #else
        return false
        #endif
    }
    public func readRecentReadings(since: Date = .distantPast) async throws -> [ExportReading] {
        #if canImport(HealthKit)
        guard isAvailable, let correlationType = HKObjectType.correlationType(forIdentifier: .bloodPressure) else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: since, end: .now, options: .strictStartDate)
            let query = HKCorrelationQuery(type: correlationType, predicate: predicate, samplePredicate: nil) { _, correlations, error in
                if let error { continuation.resume(throwing: error); return }
                let results = (correlations ?? []).compactMap { correlation -> ExportReading? in
                    let samples = correlation.objects.compactMap { $0 as? HKQuantitySample }
                    guard let systolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic), let diastolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic), let systolicSample = samples.first(where: { $0.quantityType.identifier == systolicType.identifier }), let diastolicSample = samples.first(where: { $0.quantityType.identifier == diastolicType.identifier }) else { return nil }
                    let pulseSample = samples.first(where: { $0.quantityType.identifier == HKQuantityType.quantityType(forIdentifier: .heartRate)?.identifier })
                    let pulse = pulseSample.map { Int($0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))) }
                    return ExportReading(date: correlation.startDate, systolic: Int(systolicSample.quantity.doubleValue(for: .millimeterOfMercury())), diastolic: Int(diastolicSample.quantity.doubleValue(for: .millimeterOfMercury())), pulse: pulse)
                }
                continuation.resume(returning: results)
            }
            store.execute(query)
        }
        #else
        return []
        #endif
    }
    public func save(_ reading: ExportReading) async throws {
        try await save(systolic: reading.systolic, diastolic: reading.diastolic, pulse: reading.pulse, measuredAt: reading.date)
    }
    public func save(systolic: Int, diastolic: Int, pulse: Int? = nil, measuredAt: Date) async throws {
        #if canImport(HealthKit)
        guard isAvailable, let systolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic), let diastolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic), let correlationType = HKObjectType.correlationType(forIdentifier: .bloodPressure) else { return }
        let systolicQuantity = HKQuantity(unit: HKUnit.millimeterOfMercury(), doubleValue: Double(systolic))
        let diastolicQuantity = HKQuantity(unit: HKUnit.millimeterOfMercury(), doubleValue: Double(diastolic))
        var samples: Set<HKSample> = [
            HKQuantitySample(type: systolicType, quantity: systolicQuantity, start: measuredAt, end: measuredAt),
            HKQuantitySample(type: diastolicType, quantity: diastolicQuantity, start: measuredAt, end: measuredAt)
        ]
        if let pulse, let pulseType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            let pulseQuantity = HKQuantity(unit: HKUnit.count().unitDivided(by: HKUnit.minute()), doubleValue: Double(pulse))
            samples.insert(HKQuantitySample(type: pulseType, quantity: pulseQuantity, start: measuredAt, end: measuredAt))
        }
        let correlation = HKCorrelation(type: correlationType, start: measuredAt, end: measuredAt, objects: samples)
        try await store.save(correlation)
        #endif
    }
    public func save(_ reading: BloodPressureReading) async throws {
        try await save(ExportReading(date: reading.measuredAt, systolic: reading.systolic, diastolic: reading.diastolic, pulse: reading.pulse, fasting: reading.fasting, note: reading.note))
    }
}

extension HealthKitService: HealthKitServicing {}
