import Foundation
import Combine

@MainActor
public final class AppContainer: ObservableObject {
    @Published public private(set) var ruleEngine: BloodPressureRuleEngine
    @Published public private(set) var dietaryEngine: DietaryAdviceRuleEngine
    public let notificationService: any NotificationServicing
    public let authenticationService: any AuthenticationServicing
    public let healthKitService: any HealthKitServicing
    public let syncService: any ReadingSyncService
    public init(standard: BPGuideline = .china,
                notificationService: (any NotificationServicing)? = nil,
                authenticationService: (any AuthenticationServicing)? = nil,
                healthKitService: (any HealthKitServicing)? = nil,
                syncService: (any ReadingSyncService)? = nil) {
        ruleEngine = BloodPressureRuleEngine(standard: standard)
        dietaryEngine = DietaryAdviceRuleEngine(engine: ruleEngine)
        self.notificationService = notificationService ?? NotificationService()
        self.authenticationService = authenticationService ?? AuthenticationService()
        self.healthKitService = healthKitService ?? HealthKitService()
        self.syncService = syncService ?? LocalOnlySyncService()
    }
    public func setGuideline(_ value: String) {
        let standard: BPGuideline = value == BPGuideline.accAha.rawValue ? .accAha : .china
        ruleEngine = BloodPressureRuleEngine(standard: standard)
        dietaryEngine = DietaryAdviceRuleEngine(engine: ruleEngine)
    }
}
