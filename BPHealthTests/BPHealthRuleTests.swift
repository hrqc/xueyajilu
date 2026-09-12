import XCTest
import SwiftData
#if SWIFT_PACKAGE
@testable import BPHealthCore
#else
@testable import BPHealth
#endif

final class BPHealthRuleTests: XCTestCase {
    let engine = BloodPressureRuleEngine()
    func testBoundaries() {
        XCTAssertEqual(engine.classify(systolic: 89, diastolic: 59).level, .low)
        XCTAssertEqual(engine.classify(systolic: 90, diastolic: 60).level, .normal)
        XCTAssertEqual(engine.classify(systolic: 119, diastolic: 79).level, .normal)
        XCTAssertEqual(engine.classify(systolic: 120, diastolic: 80).level, .elevated)
        XCTAssertEqual(engine.classify(systolic: 129, diastolic: 79).level, .elevated)
        XCTAssertEqual(engine.classify(systolic: 130, diastolic: 80).level, .elevated)
        XCTAssertEqual(engine.classify(systolic: 139, diastolic: 89).level, .elevated)
        XCTAssertEqual(engine.classify(systolic: 140, diastolic: 90).level, .stage1)
        XCTAssertEqual(engine.classify(systolic: 160, diastolic: 100).level, .stage2)
        XCTAssertEqual(engine.classify(systolic: 180, diastolic: 120).level, .stage3)
        XCTAssertEqual(engine.classify(systolic: 181, diastolic: 121).level, .crisis)
    }

    func testBoundaryClassificationCarriesSafetyMetadata() {
        let low = engine.classify(systolic: 89, diastolic: 59)
        XCTAssertFalse(low.isUrgent)
        XCTAssertFalse(low.explanation.isEmpty)
        XCTAssertFalse(low.action.isEmpty)
        XCTAssertFalse(low.level.colorName.isEmpty)

        let crisis = engine.classify(systolic: 181, diastolic: 121)
        XCTAssertTrue(crisis.isUrgent)
        XCTAssertTrue(crisis.action.contains("就医"))
        XCTAssertEqual(crisis.colorName, crisis.level.colorName)

        let mixedExtreme = engine.classify(systolic: 89, diastolic: 200)
        XCTAssertTrue(mixedExtreme.isUrgent)
        XCTAssertEqual(mixedExtreme.level, .crisis)
    }
    func testValidation() {
        XCTAssertTrue(ReadingValidator().validate(systolic: 120, diastolic: 80, pulse: 70, measuredAt: .now).isValid)
        XCTAssertFalse(ReadingValidator().validate(systolic: 40, diastolic: 80, pulse: nil, measuredAt: .now).isValid)
        XCTAssertTrue(ReadingValidator().validate(systolic: 120, diastolic: 80, pulse: nil, measuredAt: .now.addingTimeInterval(3600)).issues.contains(.futureDateWarning))
    }
    func testPediatricNeedsHeight() {
        let p = UserProfile(ageOverride: 10, sex: "女")
        XCTAssertEqual(engine.classify(systolic: 120, diastolic: 80, profile: p).level, .pediatricEvaluation)
        let infant = UserProfile(ageOverride: 1, sex: "男", heightCm: 75)
        XCTAssertEqual(engine.classify(systolic: 120, diastolic: 80, profile: infant).level, .pediatricEvaluation)
        let toddler = UserProfile(ageOverride: 2, sex: "男", heightCm: 90)
        XCTAssertEqual(engine.classify(systolic: 120, diastolic: 80, profile: toddler).level, .pediatricEvaluation)
        XCTAssertTrue(engine.classify(systolic: 120, diastolic: 80, profile: toddler).action.contains("儿科"))
        let pediatricCrisis = UserProfile(ageOverride: 10, sex: "女", heightCm: 140)
        let urgent = engine.classify(systolic: 181, diastolic: 121, profile: pediatricCrisis)
        XCTAssertEqual(urgent.level, .pediatricEvaluation)
        XCTAssertTrue(urgent.isUrgent)
    }
    func testPediatricPercentileProviderIsConfigurable() {
        let threshold = PediatricPercentileThreshold(age: 10, sex: "女", heightCm: 130...150, systolic90: 110, systolic95: 115, diastolic90: 70, diastolic95: 75)
        let pediatricEngine = BloodPressureRuleEngine(pediatricEvaluator: PediatricPercentileEvaluator(thresholds: [threshold]))
        let profile = UserProfile(ageOverride: 10, sex: "女", heightCm: 140)
        XCTAssertTrue(pediatricEngine.classify(systolic: 116, diastolic: 76, profile: profile).explanation.contains("95"))
    }

    func testDefaultPediatricReferenceUsesAgeSexAndHeight() {
        let profile = UserProfile(ageOverride: 10, sex: "女", heightCm: 140)
        let result = engine.classify(systolic: 114, diastolic: 76, profile: profile)
        XCTAssertTrue(result.explanation.contains("90") || result.explanation.contains("95") || result.action.contains("复测"))
        let shorter = UserProfile(ageOverride: 10, sex: "女", heightCm: 110)
        let shorterResult = engine.classify(systolic: 110, diastolic: 70, profile: shorter)
        XCTAssertEqual(shorterResult.level, .pediatricEvaluation)
    }

    func testProfileComputedBMIAndAgeOverride() {
        let p = UserProfile(ageOverride: 66, heightCm: 170, weightKg: 68)
        XCTAssertEqual(p.age, 66)
        XCTAssertEqual(p.bmi ?? 0, 68.0 / (1.7 * 1.7), accuracy: 0.001)
        let elderly = engine.classify(systolic: 130, diastolic: 80, profile: p)
        XCTAssertTrue(elderly.explanation.contains("个体化"))
        let elderlyAdvice = DietaryAdviceRuleEngine().advice(for: BloodPressureReading(systolic: 130, diastolic: 80), profile: p)
        XCTAssertTrue(elderlyAdvice.contains { $0.text.contains("老年人") })
    }

    func testAdultSexDoesNotChangeClassificationThreshold() {
        let female = UserProfile(ageOverride: 30, sex: "女")
        let male = UserProfile(ageOverride: 30, sex: "男")
        let femaleResult = engine.classify(systolic: 140, diastolic: 90, profile: female)
        let maleResult = engine.classify(systolic: 140, diastolic: 90, profile: male)
        XCTAssertEqual(femaleResult.level, .stage1)
        XCTAssertEqual(maleResult.level, .stage1)
        XCTAssertTrue(femaleResult.explanation.contains("性别"))
        XCTAssertTrue(maleResult.explanation.contains("性别"))
    }

    func testProfileWithoutBirthDateHasUnknownAge() {
        XCTAssertNil(UserProfile().age)
    }

    func testAgeBoundarySwitchesFromPediatricToAdultPath() {
        let child = UserProfile(ageOverride: 17, sex: "男", heightCm: 150)
        let adult = UserProfile(ageOverride: 18, sex: "男", heightCm: 150)
        XCTAssertEqual(engine.classify(systolic: 140, diastolic: 90, profile: child).level, .pediatricEvaluation)
        XCTAssertEqual(engine.classify(systolic: 140, diastolic: 90, profile: adult).level, .stage1)
    }

    func testBirthDateAgeUsesInjectedCalendarAndReferenceDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(identifier: "GMT") ?? TimeZone.current
        let birth = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2008, month: 9, day: 12)) ?? .distantPast
        let beforeBirthday = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 9, day: 11)) ?? .distantPast
        let birthday = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 9, day: 12)) ?? .distantPast
        let profile = UserProfile(birthDate: birth)
        XCTAssertEqual(profile.age(asOf: beforeBirthday, calendar: calendar), 17)
        XCTAssertEqual(profile.age(asOf: birthday, calendar: calendar), 18)
    }

    func testCSVExporterEscapesFieldsAndSortsByMeasurementTime() {
        let older = BloodPressureReading(measuredAt: Date(timeIntervalSince1970: 100), systolic: 120, diastolic: 80, note: "早,测量")
        let newer = BloodPressureReading(measuredAt: Date(timeIntervalSince1970: 200), systolic: 130, diastolic: 85, note: "引号\"备注")
        let csv = CSVExporter().export([newer, older])
        let rows = csv.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows[1].contains("早,测量"))
        XCTAssertTrue(rows[2].contains("引号\"\"备注"))
        XCTAssertTrue(rows[1].hasPrefix("\"1970-01-01T00:01:40Z\""))
    }

    func testCSVExporterSupportsEnglishHeadersAndBooleanValues() {
        let reading = BloodPressureReading(systolic: 120, diastolic: 80, arm: .left, position: .sitting, mood: .calm, exerciseBefore: true, medicationTaken: true, fasting: true)
        let csv = CSVExporter().export([reading], language: .english)
        XCTAssertTrue(csv.hasPrefix("Measured at,Systolic,Diastolic,Pulse,Fasting"))
        XCTAssertTrue(csv.contains("\"Yes\""))
        XCTAssertTrue(csv.contains("\"Left\""))
        XCTAssertTrue(csv.contains("\"Sitting\""))
        XCTAssertTrue(csv.contains("\"Calm\""))
        XCTAssertFalse(csv.contains("空腹"))
    }

    @MainActor
    func testRepositoryPersistsAndFiltersInMemorySwiftData() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: BloodPressureReading.self, UserProfile.self, configurations: configuration)
        let repository = ReadingRepository(context: container.mainContext)
        let fasting = BloodPressureReading(measuredAt: Date(timeIntervalSince1970: 100), systolic: 120, diastolic: 80, note: "晨间", fasting: true)
        try repository.save(fasting)
        XCTAssertEqual(try repository.fetch(search: "晨间", fasting: true).count, 1)
        XCTAssertEqual(try repository.fetch(fasting: false).count, 0)
        fasting.note = "已编辑"
        try repository.update(fasting)
        XCTAssertEqual(try repository.fetch(search: "已编辑").count, 1)
        try repository.delete(fasting)
        XCTAssertTrue(try repository.fetch().isEmpty)
    }

#if !SWIFT_PACKAGE
    @MainActor
    func testProfileRoundTripPersistsSpecialPopulationFields() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: BloodPressureReading.self, UserProfile.self, configurations: configuration)
        let store = BPUIStore(context: container.mainContext)
        store.profile.name = "测试用户"
        store.profile.ageOverride = 17
        store.profile.gender = "女"
        store.profile.height = 160
        store.profile.weight = 55
        store.profile.pregnant = true
        store.profile.chronicConditions = ["肾病", "糖尿病"]
        store.profile.otherChronicConditions = "甲状腺"
        store.profile.medication = "示例药物"
        store.profile.targetRange = "100-130/65-85 mmHg"
        store.saveProfile()

        let reloaded = BPUIStore(context: container.mainContext)
        reloaded.loadProfile()
        XCTAssertEqual(reloaded.profile.name, "测试用户")
        XCTAssertEqual(reloaded.profile.ageOverride, 17)
        XCTAssertEqual(reloaded.profile.gender, "女")
        XCTAssertEqual(reloaded.profile.height, 160, accuracy: 0.001)
        XCTAssertEqual(reloaded.profile.weight, 55, accuracy: 0.001)
        XCTAssertTrue(reloaded.profile.pregnant)
        XCTAssertTrue(reloaded.profile.chronicConditions.contains("肾病"))
        XCTAssertTrue(reloaded.profile.chronicConditions.contains("糖尿病"))
        XCTAssertEqual(reloaded.profile.medication, "示例药物")
        XCTAssertEqual(reloaded.profile.targetRange, "100-130/65-85 mmHg")
    }

    @MainActor
    func testClearAllLocalDataRemovesRecordsProfilesAndAppSettings() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: BloodPressureReading.self, UserProfile.self, configurations: configuration)
        let store = BPUIStore(context: container.mainContext)
        store.add(BPUIReading(systolic: 120, diastolic: 80), syncHealthKit: false)
        store.profile.name = "待删除"
        store.saveProfile()
        UserDefaults.standard.set(true, forKey: "bphealth.reminderEnabled")
        UserDefaults.standard.set("en", forKey: "bphealth.language")
        store.clearAllLocalData()
        XCTAssertTrue(store.readings.isEmpty)
        XCTAssertNil(try container.mainContext.fetch(FetchDescriptor<UserProfile>()).first)
        XCTAssertNil(UserDefaults.standard.object(forKey: "bphealth.reminderEnabled"))
        XCTAssertNil(UserDefaults.standard.object(forKey: "bphealth.language"))
    }
#endif

    func testDashboardStatsComputesTargetRateAndMorningEveningAverages() {
        let calendar = Calendar.current
        let day = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1)) ?? Date(timeIntervalSince1970: 0)
        let morning = BloodPressureReading(measuredAt: day.addingTimeInterval(8 * 3600), systolic: 120, diastolic: 80, pulse: 60)
        let evening = BloodPressureReading(measuredAt: day.addingTimeInterval(19 * 3600), systolic: 140, diastolic: 90, pulse: 80)
        let target = UserProfile(targetSystolicMin: 110, targetSystolicMax: 130, targetDiastolicMin: 70, targetDiastolicMax: 85)
        let stats = DashboardStats(readings: [morning, evening], target: target)
        XCTAssertEqual(stats.targetRate, 0.5, accuracy: 0.0001)
        XCTAssertEqual(stats.morningAverage ?? 0, 120, accuracy: 0.001)
        XCTAssertEqual(stats.eveningAverage ?? 0, 140, accuracy: 0.001)
        XCTAssertEqual(stats.averagePulse ?? 0, 70, accuracy: 0.001)
        XCTAssertEqual(stats.lowestDiastolic, 80)
        XCTAssertEqual(stats.highestPulse, 80)
        XCTAssertEqual(stats.morningPulseAverage ?? 0, 60, accuracy: 0.001)
        XCTAssertEqual(stats.morningDiastolicAverage ?? 0, 80, accuracy: 0.001)
        XCTAssertEqual(stats.eveningDiastolicAverage ?? 0, 90, accuracy: 0.001)
    }

    func testDashboardStatsUsesInjectedTimezoneForMorningAndEvening() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(identifier: "GMT") ?? TimeZone.current
        let morningDate = utc.date(from: DateComponents(timeZone: utc.timeZone, year: 2025, month: 1, day: 1, hour: 8)) ?? .distantPast
        let eveningDate = utc.date(from: DateComponents(timeZone: utc.timeZone, year: 2025, month: 1, day: 1, hour: 19)) ?? .distantPast
        let stats = DashboardStats(readings: [BloodPressureReading(measuredAt: morningDate, systolic: 120, diastolic: 80), BloodPressureReading(measuredAt: eveningDate, systolic: 140, diastolic: 90)], calendar: utc)
        XCTAssertEqual(stats.morningAverage ?? 0, 120, accuracy: 0.001)
        XCTAssertEqual(stats.eveningAverage ?? 0, 140, accuracy: 0.001)
    }
    func testKidneyDiseaseSuppressesPotassiumAdvice() {
        let p = UserProfile(kidneyDisease: true)
        let r = BloodPressureReading(systolic: 150, diastolic: 95)
        XCTAssertFalse(DietaryAdviceRuleEngine().advice(for: r, profile: p).contains { $0.text.contains("钾") })
    }

    func testCrisisAdvicePrioritizesUrgentAssessment() {
        let reading = BloodPressureReading(systolic: 181, diastolic: 121)
        let advice = DietaryAdviceRuleEngine().advice(for: reading)
        XCTAssertTrue(advice.first?.text.contains("危象") == true)
        XCTAssertTrue(advice.allSatisfy { $0.disclaimer.contains("非诊断") })
    }

    func testPediatricUrgentClassificationKeepsUrgentAdvice() {
        let profile = UserProfile(ageOverride: 10, sex: "男", heightCm: 140)
        let reading = BloodPressureReading(systolic: 181, diastolic: 121)
        let classification = engine.classify(systolic: reading.systolic, diastolic: reading.diastolic, profile: profile)
        XCTAssertTrue(classification.isUrgent)
        let advice = DietaryAdviceRuleEngine().advice(for: reading, profile: profile)
        XCTAssertTrue(advice.first?.text.contains("紧急范围") == true)
        XCTAssertTrue(advice.allSatisfy { $0.disclaimer.contains("非诊断") })
    }

    func testAdviceCarriesNonDiagnosticDisclaimerAndSpecialPopulationContext() {
        let profile = UserProfile(ageOverride: 40, sex: "女", pregnant: true, diabetes: true)
        let reading = BloodPressureReading(systolic: 85, diastolic: 55, fasting: true)
        let advice = DietaryAdviceRuleEngine().advice(for: reading, profile: profile)
        XCTAssertFalse(advice.isEmpty)
        XCTAssertTrue(advice.allSatisfy { $0.disclaimer.contains("非诊断") })
        XCTAssertTrue(advice.contains { $0.text.contains("适量增加盐分") })
        XCTAssertTrue(advice.contains { $0.text.contains("孕期") })
        XCTAssertTrue(advice.contains { $0.text.contains("空腹") })
        XCTAssertFalse(advice.first?.englishText.isEmpty ?? true)
    }

    func testRoutineAdviceHasEnglishCopyAndDisclaimer() {
        let items = [AdviceItem(text: "测量前静坐 5 分钟，保持袖带与心脏同高"), AdviceItem(text: "保持规律运动与充足睡眠")]
        XCTAssertTrue(items.allSatisfy { !$0.englishText.isEmpty && $0.englishText != $0.text })
        XCTAssertTrue(items.allSatisfy { $0.disclaimer == "非诊断，仅供参考" })
    }

    func testClassificationProvidesEnglishDisplayCopyAndExplicitColor() {
        let classification = engine.classify(systolic: 181, diastolic: 121)
        XCTAssertEqual(classification.displayLevel(language: .english), "Hypertensive crisis")
        XCTAssertFalse(classification.displayExplanation(language: .english).isEmpty)
        XCTAssertFalse(classification.displayAction(language: .english).isEmpty)
        XCTAssertEqual(classification.colorName, "purple")
    }

    func testEnglishClassificationPreservesOlderAdultSafetyContext() {
        let classification = engine.classify(systolic: 140, diastolic: 90, profile: UserProfile(ageOverride: 70, sex: "女"))
        XCTAssertTrue(classification.displayExplanation(language: .english).contains("Older adults"))
        XCTAssertTrue(classification.displayAction(language: .english).contains("Older adults"))
    }

    func testGuidelineSwitchChangesAdultThreshold() {
        XCTAssertEqual(BloodPressureRuleEngine(standard: .china).classify(systolic: 130, diastolic: 80).level, .elevated)
        XCTAssertEqual(BloodPressureRuleEngine(standard: .accAha).classify(systolic: 130, diastolic: 80).level, .stage1)
        XCTAssertEqual(BloodPressureRuleEngine(standard: .china).classify(systolic: 180, diastolic: 110).level, .stage3)
        XCTAssertEqual(BloodPressureRuleEngine(standard: .accAha).classify(systolic: 180, diastolic: 110).level, .stage2)
    }

    func testPregnancyDiabetesAndFastingAdviceAreIncluded() {
        let profile = UserProfile(pregnant: true, diabetes: true, heartDisease: true)
        let reading = BloodPressureReading(systolic: 145, diastolic: 92, fasting: true)
        let advice = DietaryAdviceRuleEngine().advice(for: reading, profile: profile)
        XCTAssertTrue(advice.contains { $0.text.contains("孕期") })
        XCTAssertTrue(advice.contains { $0.text.contains("糖尿病") })
        XCTAssertTrue(advice.contains { $0.text.contains("心脏病") })
        XCTAssertTrue(advice.contains { $0.text.contains("空腹") })
        XCTAssertTrue(advice.allSatisfy { $0.disclaimer.contains("非诊断") })
    }

    func testValidatorAcceptsRangeEdgesAndRejectsOutOfRangePulse() {
        let validator = ReadingValidator()
        XCTAssertTrue(validator.validate(systolic: 50, diastolic: 30, pulse: 30, measuredAt: .now).isValid)
        XCTAssertTrue(validator.validate(systolic: 300, diastolic: 200, pulse: 250, measuredAt: .now).isValid)
        XCTAssertFalse(validator.validate(systolic: 120, diastolic: 80, pulse: 29, measuredAt: .now).isValid)
        XCTAssertFalse(validator.validate(systolic: 120, diastolic: 80, pulse: 251, measuredAt: .now).isValid)
    }

    func testFutureDateWarningUsesInjectedNowAndBoundaryIsStable() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let validator = ReadingValidator()
        XCTAssertFalse(validator.validate(systolic: 120, diastolic: 80, pulse: nil, measuredAt: now, now: now).issues.contains(.futureDateWarning))
        XCTAssertTrue(validator.validate(systolic: 120, diastolic: 80, pulse: nil, measuredAt: now.addingTimeInterval(1), now: now).issues.contains(.futureDateWarning))
    }

    func testCSVUsesStableUTCOrderingAcrossTimeZones() {
        let first = BloodPressureReading(measuredAt: Date(timeIntervalSince1970: 0), systolic: 120, diastolic: 80)
        let second = BloodPressureReading(measuredAt: Date(timeIntervalSince1970: 3_600), systolic: 121, diastolic: 81)
        let csv = CSVExporter().export([second, first])
        XCTAssertTrue(csv.split(separator: "\n")[1].contains("1970-01-01T00:00:00Z"))
    }

    func testDashboardStatsHandlesTenThousandReadings() {
        let readings = (0..<10_000).map { index in
            BloodPressureReading(measuredAt: Date(timeIntervalSince1970: TimeInterval(index)), systolic: 110 + index % 50, diastolic: 70 + index % 20)
        }
        measure {
            _ = DashboardStats(readings: readings)
        }
    }

    func testTrendSamplerBoundsTenThousandPoints() {
        let indices = TrendSampler.indices(count: 10_000)
        XCTAssertFalse(indices.isEmpty)
        XCTAssertLessThanOrEqual(indices.count, 500)
        XCTAssertEqual(indices.first, 0)
        XCTAssertEqual(indices.last, 9_999)
        XCTAssertTrue(indices.allSatisfy { (0..<10_000).contains($0) })
        XCTAssertEqual(indices, indices.sorted())
    }

    func testTenThousandReadingListProjectionAndTrendSamplingPerformance() {
        // 拆成独立子表达式并标出闭包返回类型：原来一行内混合取模运算与 Int? 三元
        // 表达式，编译器推不出类型，报 "unable to type-check this expression in
        // reasonable time"。语义与拆分前完全一致。
        let readings = (0..<10_000).map { (index: Int) -> BloodPressureReading in
            let measuredAt = Date(timeIntervalSince1970: TimeInterval(index))
            let systolic = 110 + index % 50
            let diastolic = 70 + index % 20
            let pulse: Int? = index % 3 == 0 ? 60 : nil
            return BloodPressureReading(measuredAt: measuredAt, systolic: systolic, diastolic: diastolic, pulse: pulse)
        }
        measure {
            let filtered = readings.filter { $0.systolic >= 120 }.sorted { $0.measuredAt > $1.measuredAt }
            _ = TrendSampler.indices(count: filtered.count, maxPoints: 500).map { filtered[$0] }
        }
    }

    @MainActor
    func testDashboardViewModelRefreshesStatsAndUsesInjectedGuideline() {
        let viewModel = DashboardViewModel()
        let reading = BloodPressureReading(systolic: 130, diastolic: 80)
        viewModel.refresh(readings: [reading], engine: BloodPressureRuleEngine(standard: .accAha))
        XCTAssertEqual(viewModel.stats.averageSystolic ?? 0, 130, accuracy: 0.001)
        XCTAssertEqual(viewModel.latestClassification?.level, .stage1)
    }

    func testLocalOnlySyncIsNoOp() async throws {
        let service = LocalOnlySyncService()
        try await service.push([])
        let downloaded = try await service.pull(since: nil)
        XCTAssertTrue(downloaded.isEmpty)
    }

    @MainActor
    func testInjectedPlatformFailuresAreHandledWithoutCrashing() async throws {
        let container = AppContainer(notificationService: DeniedNotificationService(), authenticationService: DeniedAuthenticationService(), healthKitService: DeniedHealthKitService())
        let notificationAuthorized = await container.notificationService.requestAuthorization()
        let notificationScheduled = await container.notificationService.scheduleDaily(at: .now)
        let authenticated = await container.authenticationService.authenticate(reason: "test")
        let healthKitAuthorized = try await container.healthKitService.requestAuthorization()
        XCTAssertFalse(notificationAuthorized)
        XCTAssertFalse(notificationScheduled)
        XCTAssertFalse(authenticated)
        XCTAssertFalse(healthKitAuthorized)
        let readings = try await container.healthKitService.readRecentReadings(since: .distantPast)
        XCTAssertTrue(readings.isEmpty)
        do {
            try await container.healthKitService.save(ExportReading(date: .now, systolic: 120, diastolic: 80))
            XCTFail("拒绝写入时应返回错误")
        } catch {
            XCTAssertTrue(error is PlatformFailure)
        }
    }

    @MainActor
    func testRepositoryCRUDSearchAndFastingFilter() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: BloodPressureReading.self, UserProfile.self, configurations: configuration)
        let repository = ReadingRepository(context: container.mainContext)
        let fasting = BloodPressureReading(systolic: 120, diastolic: 80, note: "晨间", fasting: true)
        let nonFasting = BloodPressureReading(systolic: 130, diastolic: 85, note: "晚间", fasting: false)
        try repository.save(fasting)
        try repository.save(nonFasting)
        XCTAssertEqual(try repository.fetch(fasting: true).count, 1)
        XCTAssertEqual(try repository.fetch(search: "130/85").count, 1)
        nonFasting.note = "已更新"
        try repository.update(nonFasting)
        XCTAssertEqual(try repository.fetch(search: "已更新").count, 1)
        try repository.delete(fasting)
        XCTAssertEqual(try repository.fetch().count, 1)
        try repository.deleteAll()
        XCTAssertTrue(try repository.fetch().isEmpty)
        let profile = UserProfile(ageOverride: 42, sex: "女")
        container.mainContext.insert(profile)
        try container.mainContext.save()
        try repository.clearAllLocalData()
        XCTAssertTrue(try repository.fetch().isEmpty)
        let profiles = try container.mainContext.fetch(FetchDescriptor<UserProfile>())
        XCTAssertTrue(profiles.isEmpty)
    }

    @MainActor
    func testReadingUseCaseDelegatesCRUD() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: BloodPressureReading.self, UserProfile.self, configurations: configuration)
        let useCase = ReadingUseCase(context: container.mainContext)
        let reading = BloodPressureReading(systolic: 118, diastolic: 76)
        try useCase.create(reading)
        XCTAssertEqual(try useCase.list().count, 1)
        XCTAssertNotNil(try useCase.find(id: reading.id))
        reading.note = "更新"
        try useCase.update(reading)
        try useCase.delete(reading)
        XCTAssertTrue(try useCase.list().isEmpty)
    }

    @MainActor
    func testReadingUseCaseRejectsInvalidInput() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: BloodPressureReading.self, UserProfile.self, configurations: configuration)
        let useCase = ReadingUseCase(context: container.mainContext)
        XCTAssertThrowsError(try useCase.create(BloodPressureReading(systolic: 80, diastolic: 90))) { error in
            XCTAssertEqual(error as? ReadingUseCaseError, .invalidInput([.systolicNotGreater]))
        }
    }

    #if canImport(UIKit)
    func testPDFExportIncludesDisclaimer() {
        let reading = BloodPressureReading(systolic: 120, diastolic: 80)
        let data = PDFExporter().exportSummary(readings: [reading])
        XCTAssertNotNil(data)
        XCTAssertTrue(data?.count ?? 0 > 100)
    }
    func testPDFExportSupportsEnglishMetadata() {
        let reading = BloodPressureReading(systolic: 120, diastolic: 80, arm: .left, position: .sitting, mood: .calm, fasting: true)
        let data = PDFExporter().exportSummary(readings: [reading], language: .english)
        XCTAssertNotNil(data)
        XCTAssertTrue(data?.count ?? 0 > 100)
    }
    func testPDFExportWrapsLongNotes() {
        let note = String(repeating: "长备注内容 ", count: 300)
        let reading = BloodPressureReading(systolic: 120, diastolic: 80, note: note)
        let data = PDFExporter().exportSummary(readings: [reading])
        XCTAssertNotNil(data)
        XCTAssertTrue(data?.count ?? 0 > 100)
    }
    #endif

    #if canImport(CryptoKit) && canImport(Security)
    func testEncryptedBackupRoundTrip() throws {
        let reading = ExportReading(date: Date(timeIntervalSince1970: 100), systolic: 120, diastolic: 80, pulse: 70, fasting: true, note: "本地备份")
        let service = LocalEncryptionService()
        let encrypted = try EncryptedBackupExporter(encryption: service).export(readings: [reading], generatedAt: Date(timeIntervalSince1970: 200))
        let decrypted = try service.decrypt(encrypted)
        XCTAssertNotEqual(encrypted, decrypted)
        XCTAssertTrue(String(data: decrypted, encoding: .utf8)?.contains("本地备份") == true)
    }
    #endif
}

private struct PlatformFailure: Error {}

@MainActor private final class DeniedNotificationService: NotificationServicing {
    func requestAuthorization() async -> Bool { false }
    func cancelDaily() {}
    func scheduleDaily(at date: Date) async -> Bool { false }
}

@MainActor private final class DeniedAuthenticationService: AuthenticationServicing {
    func authenticate(reason: String) async -> Bool { false }
}

@MainActor private final class DeniedHealthKitService: HealthKitServicing {
    var isAvailable = false
    func requestAuthorization() async throws -> Bool { false }
    func readRecentReadings(since: Date) async throws -> [ExportReading] { [] }
    func save(_ reading: ExportReading) async throws { throw PlatformFailure() }
    func save(systolic: Int, diastolic: Int, pulse: Int?, measuredAt: Date) async throws { throw PlatformFailure() }
}
