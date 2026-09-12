import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if canImport(Charts)
import Charts
#endif

/// UI 层的轻量数据模型。AppContainer 可通过 BPUIStore.replace(readings:) 注入 SwiftData 数据。
public struct BPUIReading: Identifiable, Equatable {
    public let id: UUID
    public var date: Date
    public var systolic: Int
    public var diastolic: Int
    public var pulse: Int?
    public var isFasting: Bool
    public var note: String
    public var classification: String
    public var arm: BPArm?
    public var position: BodyPosition?
    public var mood: Mood?
    public var exerciseBefore: Bool
    public var medicationTaken: Bool

    public init(id: UUID = UUID(), date: Date = .now, systolic: Int, diastolic: Int,
                pulse: Int? = nil, isFasting: Bool = false, note: String = "", classification: String = "",
                arm: BPArm? = nil, position: BodyPosition? = nil, mood: Mood? = nil, exerciseBefore: Bool = false, medicationTaken: Bool = false) {
        self.id = id; self.date = date; self.systolic = systolic; self.diastolic = diastolic
        self.pulse = pulse; self.isFasting = isFasting; self.note = note; self.classification = classification
        self.arm = arm; self.position = position; self.mood = mood; self.exerciseBefore = exerciseBefore; self.medicationTaken = medicationTaken
    }
}

@MainActor
public final class BPUIStore: ObservableObject {
    @Published public var readings: [BPUIReading]
    @Published public var reminderEnabled: Bool {
        didSet { UserDefaults.standard.set(reminderEnabled, forKey: "bphealth.reminderEnabled") }
    }
    @Published public var reminderDate: Date {
        didSet { UserDefaults.standard.set(reminderDate, forKey: "bphealth.reminderDate") }
    }
    @Published public var healthKitSyncEnabled: Bool
    @Published public var selectedStandard: String
    @Published public var persistenceMessage = ""
    /// 由 Core.RuleEngine 注入；默认值仅用于 UI 独立预览。
    public var classificationProvider: @MainActor (Int, Int) -> String = { systolic, diastolic in
        BloodPressureRuleEngine().classify(systolic: systolic, diastolic: diastolic).level.rawValue
    }
    public func classify(_ systolic: Int, _ diastolic: Int) -> String {
        dependencies.ruleEngine.classify(systolic: systolic, diastolic: diastolic, profile: coreProfile).level.rawValue
    }
    @Published public var profile = BPUIProfile()
    public let dependencies: AppContainer
    private var modelContext: ModelContext?
    private var readingUseCase: ReadingUseCase?

    public init(readings: [BPUIReading] = [], context: ModelContext? = nil, dependencies: AppContainer? = nil) {
        self.readings = readings.sorted { $0.date > $1.date }
        self.modelContext = context
        self.readingUseCase = context.map { ReadingUseCase(context: $0) }
        self.dependencies = dependencies ?? AppContainer()
        self.reminderEnabled = UserDefaults.standard.bool(forKey: "bphealth.reminderEnabled")
        self.reminderDate = (UserDefaults.standard.object(forKey: "bphealth.reminderDate") as? Date) ?? Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now) ?? .now
        self.healthKitSyncEnabled = UserDefaults.standard.bool(forKey: "bphealth.healthKitSyncEnabled")
        self.selectedStandard = UserDefaults.standard.string(forKey: "bphealth.guideline") ?? "中国指南"
        self.dependencies.setGuideline(self.selectedStandard)
        let activeDependencies = self.dependencies
        self.classificationProvider = { [activeDependencies] systolic, diastolic in activeDependencies.ruleEngine.classify(systolic: systolic, diastolic: diastolic).level.rawValue }
    }
    @discardableResult public func add(_ reading: BPUIReading, syncHealthKit: Bool = true) -> Bool {
        readings.insert(reading, at: 0); readings.sort { $0.date > $1.date }
        if !persist(reading, syncHealthKit: syncHealthKit) {
            readings.removeAll { $0.id == reading.id }
            return false
        }
        return true
    }
    public func update(_ reading: BPUIReading) {
        let previous = readings.first(where: { $0.id == reading.id })
        if let i = readings.firstIndex(where: { $0.id == reading.id }) { readings[i] = reading; readings.sort { $0.date > $1.date } }
        if let model = findModel(id: reading.id) {
            copy(reading, to: model)
            do {
                try readingUseCase?.update(model)
                syncToHealthKitIfEnabled(model)
                persistenceMessage = ""
            } catch {
                if let previous, let index = readings.firstIndex(where: { $0.id == reading.id }) { readings[index] = previous; readings.sort { $0.date > $1.date } }
                if let previous { copy(previous, to: model) }
                reportPersistenceError(error)
            }
        }
    }
    public func remove(_ reading: BPUIReading) {
        readings.removeAll { $0.id == reading.id }
        if let model = findModel(id: reading.id) {
            do {
                try readingUseCase?.delete(model)
                persistenceMessage = ""
            } catch {
                readings.append(reading)
                readings.sort { $0.date > $1.date }
                modelContext?.insert(model)
                reportPersistenceError(error)
            }
        }
    }
    public func clearAllLocalData() {
        let backup = readings
        let profileBackup = profile
        do {
            try readingUseCase?.clearAllLocalData()
            readings = []
            profile = BPUIProfile()
            reminderEnabled = false
            reminderDate = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now) ?? .now
            healthKitSyncEnabled = false
            selectedStandard = BPGuideline.china.rawValue
            dependencies.setGuideline(selectedStandard)
            dependencies.notificationService.cancelDaily()
            ["bphealth.reminderEnabled", "bphealth.reminderDate", "bphealth.healthKitSyncEnabled", "bphealth.guideline", "bphealth.lockEnabled", "bphealth.language"].forEach { UserDefaults.standard.removeObject(forKey: $0) }
            persistenceMessage = ""
        } catch {
            modelContext?.rollback()
            readings = backup
            profile = profileBackup
            reportPersistenceError(error)
        }
    }
    public func replace(readings: [BPUIReading]) { self.readings = readings.sorted { $0.date > $1.date } }
    public var coreProfile: UserProfile {
        let target = parseTargetRange(profile.targetRange)
        let sex = profile.gender == "未设置" ? "未说明" : profile.gender
        return UserProfile(birthDate: profile.birthDate, ageOverride: profile.ageOverride, sex: sex, heightCm: profile.height > 0 ? profile.height : nil, weightKg: profile.weight > 0 ? profile.weight : nil, pregnant: profile.pregnant, kidneyDisease: profile.chronicConditions.contains("肾病"), diabetes: profile.chronicConditions.contains("糖尿病"), heartDisease: profile.chronicConditions.contains("心脏病"), otherChronicConditions: profile.otherChronicConditions, currentMedication: profile.medication, targetSystolicMin: target.systolicMin, targetSystolicMax: target.systolicMax, targetDiastolicMin: target.diastolicMin, targetDiastolicMax: target.diastolicMax)
    }
    public func loadProfile() {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<UserProfile>()
        let models: [UserProfile]
        do {
            models = try modelContext.fetch(descriptor)
        } catch {
            reportPersistenceError(error)
            return
        }
        guard let model = models.first else { return }
        profile.name = model.name; profile.birthDate = model.birthDate; profile.ageOverride = model.ageOverride; profile.gender = model.sex == "未说明" ? "未设置" : model.sex; profile.height = model.heightCm ?? 0; profile.weight = model.weightKg ?? 0; profile.pregnant = model.pregnant; profile.medication = model.currentMedication
        profile.targetRange = "\(model.targetSystolicMin)-\(model.targetSystolicMax)/\(model.targetDiastolicMin)-\(model.targetDiastolicMax) mmHg"
        profile.chronicConditions = Set([model.kidneyDisease ? "肾病" : nil, model.diabetes ? "糖尿病" : nil, model.heartDisease ? "心脏病" : nil].compactMap { $0 })
        profile.otherChronicConditions = model.otherChronicConditions
    }
    public func saveProfile() {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<UserProfile>()
        let existing: [UserProfile]
        do {
            existing = try modelContext.fetch(descriptor)
        } catch {
            reportPersistenceError(error)
            return
        }
        let model = existing.first ?? UserProfile()
        model.name = profile.name; model.birthDate = profile.birthDate; model.ageOverride = profile.ageOverride; model.sex = profile.gender == "未设置" ? "未说明" : profile.gender; model.heightCm = profile.height > 0 ? profile.height : nil; model.weightKg = profile.weight > 0 ? profile.weight : nil
        model.pregnant = profile.pregnant; model.kidneyDisease = profile.chronicConditions.contains("肾病"); model.diabetes = profile.chronicConditions.contains("糖尿病"); model.heartDisease = profile.chronicConditions.contains("心脏病"); model.otherChronicConditions = profile.otherChronicConditions; model.currentMedication = profile.medication
        let target = parseTargetRange(profile.targetRange)
        model.targetSystolicMin = target.systolicMin; model.targetSystolicMax = target.systolicMax; model.targetDiastolicMin = target.diastolicMin; model.targetDiastolicMax = target.diastolicMax
        if existing.isEmpty { modelContext.insert(model) }
        do {
            try modelContext.save()
            persistenceMessage = ""
        } catch {
            reportPersistenceError(error)
        }
    }
    private func findModel(id: UUID) -> BloodPressureReading? {
        guard let readingUseCase else { return nil }
        do {
            return try readingUseCase.find(id: id)
        } catch {
            reportPersistenceError(error)
            return nil
        }
    }
    private func copy(_ reading: BPUIReading, to model: BloodPressureReading) {
        model.measuredAt = reading.date; model.systolic = reading.systolic; model.diastolic = reading.diastolic; model.pulse = reading.pulse
        model.fasting = reading.isFasting; model.note = reading.note; model.arm = reading.arm; model.position = reading.position; model.mood = reading.mood
        model.exerciseBefore = reading.exerciseBefore; model.medicationTaken = reading.medicationTaken; model.updatedAt = .now
    }
    private func persist(_ reading: BPUIReading, syncHealthKit: Bool) -> Bool {
        guard let readingUseCase else { return true }
        let model = BloodPressureReading(id: reading.id, measuredAt: reading.date, systolic: reading.systolic, diastolic: reading.diastolic, pulse: reading.pulse, note: reading.note, arm: reading.arm, position: reading.position, mood: reading.mood, exerciseBefore: reading.exerciseBefore, medicationTaken: reading.medicationTaken, fasting: reading.isFasting)
        do {
            try readingUseCase.create(model)
            if syncHealthKit { syncToHealthKitIfEnabled(model) }
            persistenceMessage = ""
            return true
        } catch {
            modelContext?.delete(model)
            reportPersistenceError(error)
            return false
        }
    }
    private func reportPersistenceError(_ error: Error) {
        _ = error
        persistenceMessage = "本地数据保存失败，请稍后重试。"
    }
    private func syncToHealthKitIfEnabled(_ model: BloodPressureReading) {
        guard healthKitSyncEnabled else { return }
        let systolic = model.systolic
        let diastolic = model.diastolic
        let pulse = model.pulse
        let measuredAt = model.measuredAt
        Task { @MainActor in
            try? await dependencies.healthKitService.save(systolic: systolic, diastolic: diastolic, pulse: pulse, measuredAt: measuredAt)
        }
    }
}

public struct BPUIProfile: Equatable {
    public var name = ""
    public var birthDate: Date?
    public var ageOverride: Int?
    public var gender = "未设置"
    public var height: Double = 0
    public var weight: Double = 0
    public var pregnant = false
    public var chronicConditions: Set<String> = []
    public var otherChronicConditions = ""
    public var medication = ""
    public var targetRange = "90-140/60-90 mmHg"
}

private func parseTargetRange(_ text: String) -> (systolicMin: Int, systolicMax: Int, diastolicMin: Int, diastolicMax: Int) {
    let defaults = (systolicMin: 90, systolicMax: 140, diastolicMin: 60, diastolicMax: 90)
    let parts = text.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
    guard parts.count == 2 else { return defaults }
    func values(_ part: Substring) -> [Int] {
        part.split(whereSeparator: { !$0.isNumber }).compactMap { Int(String($0)) }
    }
    let systolic = values(parts[0])
    let diastolic = values(parts[1])
    guard let systolicFirst = systolic.first, let diastolicFirst = diastolic.first else { return defaults }
    let systolicMax = systolic.dropFirst().first ?? systolicFirst
    let diastolicMax = diastolic.dropFirst().first ?? diastolicFirst
    return (min(systolicFirst, systolicMax), max(systolicFirst, systolicMax), min(diastolicFirst, diastolicMax), max(diastolicFirst, diastolicMax))
}

private let bpDisclaimer = "本应用不能替代医生诊断，如有不适请及时就医。"

private func bpClassificationColor(_ level: BPLevel) -> Color {
    switch level.colorName {
    case "blue": .blue
    case "green": .green
    case "yellow": .brown
    case "orange": .orange
    case "red": .red
    case "purple": .purple
    default: .gray
    }
}

public extension BPUIReading {
    init(model: BloodPressureReading) {
        self.init(id: model.id, date: model.measuredAt, systolic: model.systolic, diastolic: model.diastolic, pulse: model.pulse, isFasting: model.fasting, note: model.note, classification: "", arm: model.arm, position: model.position, mood: model.mood, exerciseBefore: model.exerciseBefore, medicationTaken: model.medicationTaken)
    }
}

private func uiReading(from model: BloodPressureReading) -> BPUIReading {
    BPUIReading(model: model)
}

@MainActor public struct BPHealthRootView: View {
    @StateObject private var store: BPUIStore
    @State private var showingAdd = false
    @AppStorage("bphealth.lockEnabled") private var lockEnabled = false
    @AppStorage("bphealth.language") private var languageRaw = AppLanguage.simplifiedChinese.rawValue
    // Start locked until the scene task confirms whether the user enabled the
    // biometric/app lock. This prevents a brief data flash while authentication
    // is still in flight when the app returns to the foreground.
    @State private var isUnlocked = false
    @Environment(\.scenePhase) private var scenePhase
    public init(store: BPUIStore? = nil) { _store = StateObject(wrappedValue: store ?? BPUIStore()) }
    public var body: some View {
        TabView {
            NavigationStack { DashboardView(store: store, showingAdd: $showingAdd) }
                .tabItem { Label(BPText.localized("tab.home", language: AppLanguage(rawValue: languageRaw) ?? .simplifiedChinese), systemImage: "house.fill") }
            NavigationStack { HistoryView(store: store) }
                .tabItem { Label(BPText.localized("tab.records", language: AppLanguage(rawValue: languageRaw) ?? .simplifiedChinese), systemImage: "list.bullet.rectangle") }
            NavigationStack { TrendsView(store: store) }
                .tabItem { Label(BPText.localized("tab.trends", language: AppLanguage(rawValue: languageRaw) ?? .simplifiedChinese), systemImage: "chart.xyaxis.line") }
            NavigationStack { AdviceView(store: store) }
                .tabItem { Label(BPText.localized("tab.advice", language: AppLanguage(rawValue: languageRaw) ?? .simplifiedChinese), systemImage: "heart.text.square") }
            NavigationStack { ProfileView(store: store) }
                .tabItem { Label(BPText.localized("tab.profile", language: AppLanguage(rawValue: languageRaw) ?? .simplifiedChinese), systemImage: "person.crop.circle") }
        }
        .sheet(isPresented: $showingAdd) { NavigationStack { AddEditReadingView(store: store) } }
        .task {
            if lockEnabled {
                isUnlocked = await store.dependencies.authenticationService.authenticate(reason: "验证身份后查看健康记录")
                if !isUnlocked { lockEnabled = false; isUnlocked = true }
            } else {
                isUnlocked = true
            }
        }
        .onChange(of: lockEnabled) { _, enabled in
            if enabled {
                isUnlocked = false
                Task { @MainActor in
                    let authenticated = await store.dependencies.authenticationService.authenticate(reason: "验证身份后查看健康记录")
                    if authenticated { isUnlocked = true } else { lockEnabled = false; isUnlocked = true }
                }
            } else {
                isUnlocked = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard lockEnabled else { return }
            if phase == .active {
                isUnlocked = false
                Task { @MainActor in isUnlocked = await store.dependencies.authenticationService.authenticate(reason: "验证身份后查看健康记录") }
            } else {
                isUnlocked = false
            }
        }
        .overlay {
            if lockEnabled && !isUnlocked {
                VStack(spacing: 16) { Image(systemName: "lock.fill").font(.largeTitle); Text("健康记录已锁定"); Button("使用 Face ID / Touch ID 解锁") { Task { @MainActor in isUnlocked = await store.dependencies.authenticationService.authenticate(reason: "验证身份后查看健康记录") } } }
                    .padding().frame(maxWidth: .infinity, maxHeight: .infinity).background(.regularMaterial)
            }
        }
        .environment(\.locale, Locale(identifier: languageRaw == AppLanguage.english.rawValue ? "en" : "zh-Hans"))
    }
}

@MainActor public struct DashboardView: View {
    @ObservedObject var store: BPUIStore
    @Binding var showingAdd: Bool
    @StateObject private var viewModel: DashboardViewModel
    @AppStorage("bphealth.language") private var languageRaw = AppLanguage.simplifiedChinese.rawValue

    public init(store: BPUIStore, showingAdd: Binding<Bool>) {
        self.store = store
        self._showingAdd = showingAdd
        self._viewModel = StateObject(wrappedValue: DashboardViewModel(engine: store.dependencies.ruleEngine))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text("血压健康").font(.largeTitle.bold()); Spacer(); Button { showingAdd = true } label: { Image(systemName: "plus.circle.fill").font(.title) }.accessibilityLabel("添加血压记录") }
                if let latest = store.readings.first { LatestReadingCard(reading: latest, ruleEngine: store.dependencies.ruleEngine, profile: store.coreProfile) } else { ContentUnavailableView("还没有记录", systemImage: "heart.text.square", description: Text("添加第一次血压测量，开始关注趋势")) }
                HStack(spacing: 12) { MetricCard(title: "平均收缩压", value: avgSystolic, unit: "mmHg"); MetricCard(title: "平均舒张压", value: avgDiastolic, unit: "mmHg") }
                HStack(spacing: 12) { MetricCard(title: "平均脉搏", value: format(stats.averagePulse), unit: "次/分"); MetricCard(title: "最低舒张压", value: formatInt(stats.lowestDiastolic), unit: "mmHg") }
                HStack(spacing: 12) { MetricCard(title: "达标率", value: String(format: "%.0f%%", stats.targetRate * 100), unit: "目标范围"); MetricCard(title: "晨/晚均值", value: "\(format(stats.morningAverage))/\(format(stats.eveningAverage))", unit: "收缩压") }
                Text(language == .english ? "Highest/lowest systolic: \(stats.highestSystolic.map(String.init) ?? "—") / \(stats.lowestSystolic.map(String.init) ?? "—") mmHg" : "最高/最低收缩压：\(stats.highestSystolic.map(String.init) ?? "—") / \(stats.lowestSystolic.map(String.init) ?? "—") mmHg").font(.subheadline).foregroundStyle(.secondary)
                NavigationLink { TrendsView(store: store) } label: { SectionHeader(title: "近期趋势", action: "查看全部") }
                MiniTrendChart(readings: Array(store.readings.prefix(7).reversed()))
                    .accessibilityLabel("最近七次血压趋势图")
                Text(bpDisclaimer).font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
            }.padding()
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { refreshViewModel() }
        .onChange(of: store.readings) { _, _ in refreshViewModel() }
        .onChange(of: store.profile) { _, _ in refreshViewModel() }
    }
    private var avgSystolic: String { format(stats.averageSystolic) }
    private var avgDiastolic: String { format(stats.averageDiastolic) }
    private var language: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .simplifiedChinese }
    private var stats: DashboardStats { viewModel.stats }
    private func format(_ value: Double?) -> String { value.map { String(Int($0.rounded())) } ?? "—" }
    private func formatInt(_ value: Int?) -> String { value.map(String.init) ?? "—" }
    private func refreshViewModel() {
        let models = store.readings.map { BloodPressureReading(measuredAt: $0.date, systolic: $0.systolic, diastolic: $0.diastolic, pulse: $0.pulse) }
        viewModel.refresh(readings: models, profile: store.coreProfile, engine: store.dependencies.ruleEngine)
    }
}

private struct LatestReadingCard: View {
    let reading: BPUIReading
    let ruleEngine: BloodPressureRuleEngine
    let profile: UserProfile
    @AppStorage("bphealth.language") private var languageRaw = AppLanguage.simplifiedChinese.rawValue
    private var classification: BPClassification { ruleEngine.classify(systolic: reading.systolic, diastolic: reading.diastolic, profile: profile) }
    private var language: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .simplifiedChinese }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("最近一次测量").font(.headline); Spacer(); Text(reading.date, style: .date).foregroundStyle(.secondary) }
            HStack(alignment: .lastTextBaseline, spacing: 4) { Text("\(reading.systolic)/\(reading.diastolic)").font(.system(.largeTitle, design: .rounded).bold()); Text("mmHg").foregroundStyle(.secondary); Spacer(); Text(classification.displayLevel(language: language)).font(.headline).foregroundStyle(classificationColor) }
            if let pulse = reading.pulse { Label(language == .english ? "Pulse \(pulse) bpm" : "脉搏 \(pulse) 次/分", systemImage: "waveform.path.ecg") .font(.subheadline).foregroundStyle(.secondary) }
            Text(classification.displayExplanation(language: language)).font(.subheadline)
            Text(classification.displayAction(language: language)).font(.footnote).foregroundStyle(.secondary)
        }.padding().background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }
    private var classificationColor: Color {
        bpClassificationColor(classification.level)
    }
}

private struct MetricCard: View { let title: String; let value: String; let unit: String; @AppStorage("bphealth.language") private var languageRaw = AppLanguage.simplifiedChinese.rawValue; private var language: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .simplifiedChinese }; var body: some View { let localizedTitle = BPText.localized(title, language: language); let localizedUnit = BPText.localized(unit, language: language); return VStack(alignment: .leading) { Text(localizedTitle).font(.subheadline).foregroundStyle(.secondary); Text(value).font(.title.bold()); Text(localizedUnit).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12)).accessibilityElement(children: .ignore).accessibilityLabel("\(localizedTitle): \(value) \(localizedUnit)") } }
private struct SectionHeader: View { let title: String; let action: String; @AppStorage("bphealth.language") private var languageRaw = AppLanguage.simplifiedChinese.rawValue; private var language: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .simplifiedChinese }; var body: some View { HStack { Text(BPText.localized(title, language: language)).font(.title3.bold()); Spacer(); Text(BPText.localized(action, language: language)).font(.subheadline).foregroundStyle(Color.accentColor) } } }

@MainActor public struct AddEditReadingView: View {
    @ObservedObject var store: BPUIStore
    private let editing: BPUIReading?
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var systolic: String
    @State private var diastolic: String
    @State private var pulse: String
    @State private var note: String
    @State private var isFasting: Bool
    @State private var arm: BPArm?
    @State private var position: BodyPosition?
    @State private var mood: Mood?
    @State private var exerciseBefore = false
    @State private var medicationTaken = false
    @State private var showFutureWarning = false
    @State private var errorMessage = ""
    @AppStorage("bphealth.language") private var languageRaw = AppLanguage.simplifiedChinese.rawValue
    public init(store: BPUIStore, editing: BPUIReading? = nil) { self.store = store; self.editing = editing; _date = State(initialValue: editing?.date ?? .now); _systolic = State(initialValue: editing.map { String($0.systolic) } ?? ""); _diastolic = State(initialValue: editing.map { String($0.diastolic) } ?? ""); _pulse = State(initialValue: editing?.pulse.map(String.init) ?? ""); _note = State(initialValue: editing?.note ?? ""); _isFasting = State(initialValue: editing?.isFasting ?? false); _arm = State(initialValue: editing?.arm); _position = State(initialValue: editing?.position); _mood = State(initialValue: editing?.mood); _exerciseBefore = State(initialValue: editing?.exerciseBefore ?? false); _medicationTaken = State(initialValue: editing?.medicationTaken ?? false) }
    public var body: some View {
        Form {
            Section("测量数值") { numericField("收缩压", text: $systolic, range: "50–300"); numericField("舒张压", text: $diastolic, range: "30–200"); numericField("脉搏（可选）", text: $pulse, range: "30–250") }
            if (!systolic.isEmpty || !diastolic.isEmpty || !pulse.isEmpty) && values == nil { Section { Text("请检查输入范围，并确保收缩压高于舒张压。输入无效时无法保存。").foregroundStyle(.red) } }
            Section("测量信息") { DatePicker("测量时间", selection: $date, displayedComponents: [.date, .hourAndMinute]); Picker("手臂", selection: $arm) { Text(BPText.localized("未设置", language: language)).tag(BPArm?.none); ForEach(BPArm.allCases, id: \.self) { Text($0.displayName(language: language)).tag(BPArm?.some($0)) } }; Picker("体位", selection: $position) { Text(BPText.localized("未设置", language: language)).tag(BodyPosition?.none); ForEach(BodyPosition.allCases, id: \.self) { Text($0.displayName(language: language)).tag(BodyPosition?.some($0)) } }; Picker("情绪", selection: $mood) { Text(BPText.localized("未设置", language: language)).tag(Mood?.none); ForEach(Mood.allCases, id: \.self) { Text($0.displayName(language: language)).tag(Mood?.some($0)) } }; Toggle("空腹测量", isOn: $isFasting); Toggle("测量前运动", isOn: $exerciseBefore); Toggle("已服药", isOn: $medicationTaken); TextField("备注（可选）", text: $note, axis: .vertical) }
            if !errorMessage.isEmpty { Section { Text(BPText.localized(errorMessage, language: language)).foregroundStyle(.red) } }
            if !store.persistenceMessage.isEmpty { Section { Text(BPText.localized(store.persistenceMessage, language: language)).foregroundStyle(.red) } }
            Section { Text(bpDisclaimer).font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle(editing == nil ? "添加记录" : "编辑记录").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(!valid) } }.alert("时间提示", isPresented: $showFutureWarning) { Button("知道了") { dismiss() } } message: { Text("测量时间晚于当前时间，记录已保存，请确认时间是否正确。") }
    }
    private func numericField(_ title: String, text: Binding<String>, range: String) -> some View { let language = AppLanguage(rawValue: languageRaw) ?? .simplifiedChinese; return HStack { TextField(BPText.localized(title, language: language), text: text).keyboardType(.numberPad); Spacer(); Text(range).font(.caption).foregroundStyle(.secondary) } }
    private var values: (Int, Int, Int?)? { guard let s = Int(systolic), let d = Int(diastolic), (50...300).contains(s), (30...200).contains(d), s > d else { return nil }; let p: Int?; if pulse.isEmpty { p = nil } else { guard let parsed = Int(pulse), (30...250).contains(parsed) else { return nil }; p = parsed }; return (s, d, p) }
    private var language: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .simplifiedChinese }
    private var valid: Bool { values != nil }
    private func save() { guard let (s, d, p) = values else { errorMessage = "请检查输入范围，并确保收缩压高于舒张压。"; return }; let isFuture = date > .now; if isFuture { errorMessage = "测量时间晚于当前时间，记录将保存并提示。" }; let item = BPUIReading(id: editing?.id ?? UUID(), date: date, systolic: s, diastolic: d, pulse: p, isFasting: isFasting, note: note, classification: store.classify(s, d), arm: arm, position: position, mood: mood, exerciseBefore: exerciseBefore, medicationTaken: medicationTaken); if editing == nil { store.add(item) } else { store.update(item) }; if !store.persistenceMessage.isEmpty { errorMessage = store.persistenceMessage; return }; if isFuture { showFutureWarning = true } else { dismiss() } }
}

@MainActor public struct HistoryView: View {
    @ObservedObject var store: BPUIStore
    @State private var query = ""
    @State private var filter = "全部"
    @State private var readingToDelete: BPUIReading?
    @State private var showDeleteConfirmation = false
    var filtered: [BPUIReading] { store.readings.filter { (filter == "全部" || (filter == "空腹" && $0.isFasting) || (filter == "非空腹" && !$0.isFasting)) && (query.isEmpty || $0.note.localizedCaseInsensitiveContains(query) || "\($0.systolic)/\($0.diastolic)".contains(query)) } }
    public var body: some View { List { ForEach(filtered) { reading in NavigationLink { AddEditReadingView(store: store, editing: reading) } label: { ReadingRow(reading: reading, ruleEngine: store.dependencies.ruleEngine, profile: store.coreProfile) }.swipeActions { Button(role: .destructive) { readingToDelete = reading; showDeleteConfirmation = true } label: { Label("删除", systemImage: "trash") } } }; if filtered.isEmpty { ContentUnavailableView("没有匹配记录", systemImage: "magnifyingglass") }; Section { Text(bpDisclaimer).font(.footnote).foregroundStyle(.secondary) } }.searchable(text: $query, prompt: "搜索数值或备注").navigationTitle("历史记录").toolbar { ToolbarItem(placement: .topBarTrailing) { Menu { Picker("筛选", selection: $filter) { Text("全部").tag("全部"); Text("空腹").tag("空腹"); Text("非空腹").tag("非空腹") } } label: { Image(systemName: "line.3.horizontal.decrease.circle") } }; ToolbarItem(placement: .topBarTrailing) { NavigationLink { AddEditReadingView(store: store) } label: { Image(systemName: "plus") } } }.confirmationDialog("确认删除这条记录？", isPresented: $showDeleteConfirmation) { Button("删除", role: .destructive) { if let readingToDelete { store.remove(readingToDelete) }; readingToDelete = nil }; Button("取消", role: .cancel) { readingToDelete = nil } } message: { Text("删除后无法从本地记录列表恢复。") } }
}
private struct ReadingRow: View {
    let reading: BPUIReading
    let ruleEngine: BloodPressureRuleEngine
    let profile: UserProfile
    @AppStorage("bphealth.language") private var languageRaw = AppLanguage.simplifiedChinese.rawValue
    private var classification: BPClassification { ruleEngine.classify(systolic: reading.systolic, diastolic: reading.diastolic, profile: profile) }
    private var language: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .simplifiedChinese }
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(reading.date, format: .dateTime.month().day().hour().minute())
                Text(BPText.localized(reading.isFasting ? "空腹" : "非空腹", language: language)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("\(reading.systolic)/\(reading.diastolic)").font(.headline)
                Text(classification.displayLevel(language: language)).font(.caption).foregroundStyle(bpClassificationColor(classification.level))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(language == .english ? "\(reading.systolic)/\(reading.diastolic), \(classification.displayLevel(language: language)), \(classification.displayExplanation(language: language)), \(classification.displayAction(language: language))" : "\(reading.systolic)/\(reading.diastolic)，\(classification.displayLevel(language: language))，\(classification.displayExplanation(language: language))，\(classification.displayAction(language: language))")
        .accessibilityIdentifier("reading-row")
    }
}

@MainActor public struct TrendsView: View {
    @ObservedObject var store: BPUIStore
    @State private var period = "7天"
    var readings: [BPUIReading] {
        let start: Date
        switch period {
        case "7天": start = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
        case "30天": start = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        case "90天": start = Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? .distantPast
        default: start = .distantPast
        }
        return store.readings.filter { $0.date >= start }.sorted { $0.date < $1.date }
    }
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("时间范围", selection: $period) {
                    Text("7天").tag("7天")
                    Text("30天").tag("30天")
                    Text("90天").tag("90天")
                    Text("全部").tag("全部")
                }
                .pickerStyle(.segmented)

                if readings.isEmpty {
                    ContentUnavailableView("暂无趋势数据", systemImage: "chart.xyaxis.line")
                } else {
#if canImport(Charts)
                    Chart(chartReadings) {
                        LineMark(x: .value("日期", $0.date), y: .value("收缩压", $0.systolic))
                            .foregroundStyle(.red)
                        LineMark(x: .value("日期", $0.date), y: .value("舒张压", $0.diastolic))
                            .foregroundStyle(.blue)
                        if let pulse = $0.pulse {
                            LineMark(x: .value("日期", $0.date), y: .value("脉搏", pulse))
                                .foregroundStyle(.green)
                        }
                    }
                    .frame(height: 260)
                    .chartYScale(domain: chartDomain)
#else
                    Text("趋势图表需在 iOS 17 Charts 环境中显示")
#endif
                    HStack {
                        MetricCard(title: "最高收缩压", value: String(readings.map(\.systolic).max() ?? 0), unit: "mmHg")
                        MetricCard(title: "最低收缩压", value: String(readings.map(\.systolic).min() ?? 0), unit: "mmHg")
                    }
                    HStack {
                        MetricCard(title: "最高舒张压", value: String(readings.map(\.diastolic).max() ?? 0), unit: "mmHg")
                        MetricCard(title: "最低舒张压", value: String(readings.map(\.diastolic).min() ?? 0), unit: "mmHg")
                    }
                    HStack {
                        MetricCard(title: "平均脉搏", value: format(statistics.averagePulse), unit: "次/分")
                        MetricCard(title: "最高脉搏", value: formatInt(statistics.highestPulse), unit: "次/分")
                    }
                    HStack {
                        MetricCard(title: "晨间均值", value: "\(format(statistics.morningAverage))/\(format(statistics.morningDiastolicAverage))", unit: "收缩压/舒张压")
                        MetricCard(title: "晚间均值", value: "\(format(statistics.eveningAverage))/\(format(statistics.eveningDiastolicAverage))", unit: "收缩压/舒张压")
                    }
                }
                Text(bpDisclaimer).font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("趋势")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("血压趋势与统计")
    }
    private var statistics: DashboardStats {
        DashboardStats(readings: readings.map { BloodPressureReading(measuredAt: $0.date, systolic: $0.systolic, diastolic: $0.diastolic, pulse: $0.pulse) })
    }
    /// 图表最多绘制 500 个点，避免长期全量数据拖慢 Swift Charts；统计仍使用完整记录。
    private var chartReadings: [BPUIReading] {
        TrendSampler.indices(count: readings.count).map { readings[$0] }
    }
    private var chartDomain: ClosedRange<Int> {
        let values = readings.flatMap { [$0.systolic, $0.diastolic, $0.pulse ?? 0] }.filter { $0 > 0 }
        guard let minimum = values.min(), let maximum = values.max() else { return 30...300 }
        let lower = max(0, minimum - 10)
        let upper = min(320, maximum + 10)
        return lower...max(lower + 1, upper)
    }
    private func format(_ value: Double?) -> String { value.map { String(Int($0.rounded())) } ?? "—" }
    private func formatInt(_ value: Int?) -> String { value.map(String.init) ?? "—" }
}

@MainActor public struct AdviceView: View {
    @ObservedObject var store: BPUIStore
    @AppStorage("bphealth.language") private var languageRaw = AppLanguage.simplifiedChinese.rawValue
    private var language: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .simplifiedChinese }
    public var body: some View {
        List {
            if let reading = store.readings.first {
                Section("基于最近一次记录") {
                    let model = BloodPressureReading(measuredAt: reading.date, systolic: reading.systolic, diastolic: reading.diastolic, pulse: reading.pulse, note: reading.note, arm: reading.arm, position: reading.position, mood: reading.mood, exerciseBefore: reading.exerciseBefore, medicationTaken: reading.medicationTaken, fasting: reading.isFasting)
                    let classification = store.dependencies.ruleEngine.classify(systolic: model.systolic, diastolic: model.diastolic, profile: store.coreProfile)
                    HStack {
                        Text("等级：\(classification.displayLevel(language: language))").font(.headline).foregroundStyle(bpClassificationColor(classification.level))
                        Text(classification.isUrgent ? (language == .english ? "Urgent" : "紧急") : (language == .english ? "Not urgent" : "非紧急"))
                            .font(.caption.bold())
                            .foregroundStyle(classification.isUrgent ? .red : .secondary)
                    }
                    Text(classification.displayExplanation(language: language))
                    Text(classification.displayAction(language: language)).font(.footnote).foregroundStyle(.secondary)
                    ForEach(store.dependencies.dietaryEngine.advice(for: model, profile: store.coreProfile)) { item in
                        VStack(alignment: .leading, spacing: 4) { Text(language == .english ? item.englishText : item.text); Text(item.disclaimer).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            Section("日常建议") {
                ForEach([AdviceItem(text: "测量前静坐 5 分钟，保持袖带与心脏同高"), AdviceItem(text: "保持规律运动与充足睡眠")]) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(language == .english ? item.englishText : item.text, systemImage: item.text.hasPrefix("测量") ? "timer" : "figure.walk")
                        Text(item.disclaimer).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section { Text(bpDisclaimer).font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("饮食与健康建议")
    }
}

@MainActor public struct ProfileView: View {
    @ObservedObject var store: BPUIStore
    @AppStorage("bphealth.language") private var languageRaw = AppLanguage.simplifiedChinese.rawValue
    private var language: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .simplifiedChinese }
    private func conditionBinding(_ value: String) -> Binding<Bool> {
        Binding(get: { store.profile.chronicConditions.contains(value) }, set: { enabled in if enabled { store.profile.chronicConditions.insert(value) } else { store.profile.chronicConditions.remove(value) } })
    }
    public var body: some View {
        List {
            Section("基本信息") {
                TextField("姓名", text: $store.profile.name)
                Picker("性别", selection: $store.profile.gender) { Text("未设置").tag("未设置"); Text("女").tag("女"); Text("男").tag("男") }
                TextField("年龄（可选）", text: Binding(get: { store.profile.ageOverride.map(String.init) ?? "" }, set: { value in
                    let age = Int(value)
                    store.profile.ageOverride = age.flatMap { $0 > 0 ? $0 : nil }
                    if let age, age > 0 { store.profile.birthDate = nil }
                }))
                .keyboardType(.numberPad)
                Toggle("填写出生日期", isOn: Binding(get: { store.profile.birthDate != nil }, set: { enabled in
                    if enabled {
                        store.profile.ageOverride = nil
                        store.profile.birthDate = Calendar.current.date(byAdding: .year, value: -30, to: .now)
                    } else {
                        store.profile.birthDate = nil
                    }
                }))
                if store.profile.birthDate != nil {
                    DatePicker("出生日期", selection: Binding(get: { store.profile.birthDate ?? .now }, set: { store.profile.birthDate = $0 }), displayedComponents: .date)
                }
                if let age = store.coreProfile.age { Text(language == .english ? "Current age: \(age)" : "当前年龄：\(age) 岁").font(.footnote).foregroundStyle(.secondary) }
                Toggle("已怀孕", isOn: $store.profile.pregnant)
            }
            Section("健康信息") {
                TextField("身高（cm）", value: $store.profile.height, format: .number)
                TextField("体重（kg）", value: $store.profile.weight, format: .number)
                Text(language == .english ? "BMI: " + (store.profile.height > 0 && store.profile.weight > 0 ? String(format: "%.1f", store.profile.weight / pow(store.profile.height / 100, 2)) : "—") : "BMI：" + (store.profile.height > 0 && store.profile.weight > 0 ? String(format: "%.1f", store.profile.weight / pow(store.profile.height / 100, 2)) : "—"))
                Toggle("肾病", isOn: conditionBinding("肾病")).accessibilityIdentifier("profile.kidneyDisease")
                Toggle("糖尿病", isOn: conditionBinding("糖尿病")).accessibilityIdentifier("profile.diabetes")
                Toggle("心脏病", isOn: conditionBinding("心脏病")).accessibilityIdentifier("profile.heartDisease")
                TextField("当前用药", text: $store.profile.medication)
                TextField("其他慢性病（可选）", text: $store.profile.otherChronicConditions)
                TextField("目标血压范围", text: $store.profile.targetRange)
            }
            if !store.persistenceMessage.isEmpty { Section { Text(BPText.localized(store.persistenceMessage, language: language)).foregroundStyle(.red) } }
            Section { Button("保存资料") { store.saveProfile() }; NavigationLink("设置") { SettingsView(store: store) }; NavigationLink("导出数据") { ExportView(store: store) }; NavigationLink("隐私与免责声明") { PrivacyDisclaimerView() } }
        }.navigationTitle("我的")
    }
}

@MainActor public struct SettingsView: View {
    @ObservedObject var store: BPUIStore
    @State private var securityMessage = ""
    @State private var healthKitMessage = ""
    @State private var reminderMessage = ""
    @State private var showDeleteAllConfirmation = false
    @AppStorage("bphealth.lockEnabled") private var lockEnabled = false
    @AppStorage("bphealth.language") private var languageRaw = AppLanguage.simplifiedChinese.rawValue
    private var language: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .simplifiedChinese }
    private func status(_ chinese: String, _ english: String) -> String { language == .english ? english : chinese }
    public var body: some View {
        Form {
            Section("语言") { Picker("界面语言", selection: $languageRaw) { ForEach(AppLanguage.allCases, id: \.rawValue) { Text($0.displayName).tag($0.rawValue) } } }
            Section("分类标准") {
                Picker("血压指南", selection: $store.selectedStandard) { Text("中国指南").tag("中国指南"); Text("ACC/AHA").tag("ACC/AHA") }
                Text("切换后新记录和建议使用对应规则。").font(.footnote).foregroundStyle(.secondary)
            }
            .onChange(of: store.selectedStandard) { _, value in
                UserDefaults.standard.set(value, forKey: "bphealth.guideline")
                store.dependencies.setGuideline(value)
                store.classificationProvider = { [dependencies = store.dependencies] systolic, diastolic in dependencies.ruleEngine.classify(systolic: systolic, diastolic: diastolic).level.rawValue }
            }
            Section("测量提醒") {
                Toggle("开启每日提醒", isOn: $store.reminderEnabled)
                    .onChange(of: store.reminderEnabled) { _, enabled in
                        Task { @MainActor in
                            let service = store.dependencies.notificationService
                            if enabled {
                                let granted = await service.requestAuthorization()
                                guard store.reminderEnabled else { return }
                                if granted {
                                    let scheduled = await service.scheduleDaily(at: store.reminderDate)
                                    if !scheduled { store.reminderEnabled = false; reminderMessage = status("提醒安排失败，请稍后重试。", "The reminder could not be scheduled. Please try again later.") }
                                } else { store.reminderEnabled = false }
                            } else { service.cancelDaily() }
                        }
                    }
                if store.reminderEnabled { DatePicker("提醒时间", selection: $store.reminderDate, displayedComponents: .hourAndMinute).onChange(of: store.reminderDate) { _, value in Task { @MainActor in if !(await store.dependencies.notificationService.scheduleDaily(at: value)) { store.reminderEnabled = false; store.dependencies.notificationService.cancelDaily(); reminderMessage = status("提醒安排失败，请稍后重试。", "The reminder could not be scheduled. Please try again later.") } } } }
                if !reminderMessage.isEmpty { Text(reminderMessage).font(.footnote).foregroundStyle(.secondary) }
            }
            Section("设备能力") {
                Toggle("使用 Face ID / Touch ID 锁定", isOn: $lockEnabled)
                Toggle("写入 HealthKit", isOn: $store.healthKitSyncEnabled)
                    .onChange(of: store.healthKitSyncEnabled) { _, enabled in
                        UserDefaults.standard.set(enabled, forKey: "bphealth.healthKitSyncEnabled")
                    }
                Button("验证 Face ID / Touch ID") { Task { @MainActor in securityMessage = await store.dependencies.authenticationService.authenticate(reason: "验证身份后查看健康记录") ? status("验证成功", "Verification succeeded") : status("设备未授权或验证失败", "Device unavailable or verification failed") } }
                if !securityMessage.isEmpty { Text(securityMessage).font(.footnote).foregroundStyle(.secondary) }
                Button("请求 HealthKit 权限") { Task { @MainActor in do { let available = try await store.dependencies.healthKitService.requestAuthorization(); healthKitMessage = available ? status("HealthKit 权限请求已返回，请在系统设置确认授权状态", "HealthKit authorization returned; check permission status in Settings") : status("HealthKit 不可用，已保留本地数据", "HealthKit is unavailable; local data was preserved") } catch { healthKitMessage = status("HealthKit 权限被拒绝或不可用", "HealthKit access was denied or unavailable") } } }
                Button("读取最近 HealthKit 数据") { Task { @MainActor in do { let values = try await store.dependencies.healthKitService.readRecentReadings(since: Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast); healthKitMessage = language == .english ? "Read \(values.count) HealthKit readings" : "已读取 \(values.count) 条 HealthKit 记录" } catch { healthKitMessage = status("HealthKit 读取失败，已保留本地数据", "HealthKit read failed; local data was preserved") } } }
                Button("导入最近 HealthKit 数据") { Task { @MainActor in await importHealthKit() } }
                Button("写入最近本地记录到 HealthKit") { let values = store.readings.prefix(20).map { ExportReading(date: $0.date, systolic: $0.systolic, diastolic: $0.diastolic, pulse: $0.pulse, fasting: $0.isFasting, note: $0.note) }; Task { @MainActor in do { for value in values { try await store.dependencies.healthKitService.save(value) }; healthKitMessage = status("已尝试写入最近本地记录", "Attempted to write recent local readings") } catch { healthKitMessage = status("HealthKit 写入失败，已保留本地数据", "HealthKit write failed; local data was preserved") } } }
                if !healthKitMessage.isEmpty { Text(healthKitMessage).font(.footnote).foregroundStyle(.secondary) }
            }
            Section("安全") { NavigationLink("隐私与免责声明") { PrivacyDisclaimerView() } }
            Section("数据管理") {
                Button("删除全部本地数据", role: .destructive) { showDeleteAllConfirmation = true }
            }
            Section { Text(bpDisclaimer).font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("设置")
        .confirmationDialog("删除全部本地数据？", isPresented: $showDeleteAllConfirmation) {
            Button("删除全部数据", role: .destructive) { store.clearAllLocalData() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法从本地记录列表恢复，请先导出需要保留的数据。")
        }
    }
    private func importHealthKit() async {
        do {
            let since = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
            let values = try await store.dependencies.healthKitService.readRecentReadings(since: since)
            var existing = store.readings
            var imported = 0
            for value in values {
                guard !existing.contains(where: { abs($0.date.timeIntervalSince(value.date)) <= 1 && $0.systolic == value.systolic && $0.diastolic == value.diastolic }) else { continue }
                let importedReading = BPUIReading(date: value.date, systolic: value.systolic, diastolic: value.diastolic, pulse: value.pulse, isFasting: value.fasting, note: value.note)
                if store.add(importedReading, syncHealthKit: false) {
                    existing.append(importedReading)
                    imported += 1
                }
            }
            healthKitMessage = language == .english ? "Imported \(imported) HealthKit readings (duplicates skipped)" : "已导入 \(imported) 条 HealthKit 记录（跳过重复项）"
        } catch {
            healthKitMessage = status("HealthKit 导入失败，已保留本地数据", "HealthKit import failed; local data was preserved")
        }
    }
}

@MainActor public struct ExportView: View {
    @ObservedObject var store: BPUIStore
    @State private var pdfData: Data?
    @State private var encryptedBackup: Data?
    @State private var exportError = ""
    @AppStorage("bphealth.language") private var languageRaw = AppLanguage.simplifiedChinese.rawValue

    private var exportReadings: [ExportReading] {
        store.readings.map { ExportReading(date: $0.date, systolic: $0.systolic, diastolic: $0.diastolic, pulse: $0.pulse, fasting: $0.isFasting, note: $0.note, arm: $0.arm, position: $0.position, mood: $0.mood, exerciseBefore: $0.exerciseBefore, medicationTaken: $0.medicationTaken) }
    }
    private var csv: String {
        let models = store.readings.map { reading in
            BloodPressureReading(id: reading.id, measuredAt: reading.date, systolic: reading.systolic, diastolic: reading.diastolic, pulse: reading.pulse, note: reading.note, arm: reading.arm, position: reading.position, mood: reading.mood, exerciseBefore: reading.exerciseBefore, medicationTaken: reading.medicationTaken, fasting: reading.isFasting)
        }
        return CSVExporter().export(models, language: AppLanguage(rawValue: languageRaw) ?? .simplifiedChinese)
    }

    public var body: some View {
        Form {
            Section("数据导出") {
                ShareLink(item: csv, subject: Text("BPHealth 血压记录")) { Label("导出 CSV", systemImage: "doc.text") }
                Button { pdfData = PDFExporter().exportSummary(readings: exportReadings, title: languageRaw == AppLanguage.english.rawValue ? "BPHealth blood pressure record" : "BPHealth 血压记录", language: AppLanguage(rawValue: languageRaw) ?? .simplifiedChinese); if pdfData == nil { exportError = languageRaw == AppLanguage.english.rawValue ? "PDF generation is unavailable on this platform." : "当前平台暂不支持 PDF 生成。" } } label: { Label("生成 PDF", systemImage: "doc.richtext") }
                if let pdfData { ShareLink(item: pdfData, preview: SharePreview("BPHealth 血压记录 PDF")) { Label("分享 PDF", systemImage: "square.and.arrow.up") } }
                Button {
                    do {
                        encryptedBackup = try EncryptedBackupExporter().export(readings: exportReadings)
                        exportError = ""
                    } catch {
                        encryptedBackup = nil
                        exportError = languageRaw == AppLanguage.english.rawValue ? "The encrypted backup could not be generated. Please try again later." : "加密备份生成失败，请稍后重试。"
                    }
                } label: { Label("生成加密备份", systemImage: "lock.doc") }
                if let encryptedBackup { ShareLink(item: encryptedBackup, preview: SharePreview("BPHealth 加密备份")) { Label("分享加密备份", systemImage: "lock.shield") } }
                if !exportError.isEmpty { Text(exportError).font(.footnote).foregroundStyle(.red) }
            }
            Section { Text("导出前请确认接收方值得信任，健康数据属于敏感个人信息。") }
            Section { Text(bpDisclaimer).font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("导出")
    }
}

@MainActor public struct PrivacyDisclaimerView: View {
    public init() {}
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("隐私与免责声明").font(.title.bold())
                Text("数据存储").font(.headline)
                Text("本应用默认将血压、个人资料和设置保存在设备本地，不会自动上传。应用删除或清除本地数据后，未导出的本地记录可能无法恢复。")
                Text("第三方权限").font(.headline)
                Text("HealthKit 仅在你授权后读取或写入；Face ID / Touch ID 仅用于本地解锁；通知权限仅用于测量提醒。当前版本不自动启用 iCloud 同步，你可以随时在系统设置中撤销权限。")
                Text("本应用不能替代医生诊断，如有不适请及时就医。血压分类和建议仅供健康管理参考，不能用于自行调整处方药物。")
            }
            .padding()
        }
        .navigationTitle("隐私")
    }
}

private struct MiniTrendChart: View {
    let readings: [BPUIReading]
    var body: some View {
#if canImport(Charts)
        Chart(readings) {
            LineMark(x: .value("日期", $0.date), y: .value("收缩压", $0.systolic))
                .foregroundStyle(.red)
            LineMark(x: .value("日期", $0.date), y: .value("舒张压", $0.diastolic))
                .foregroundStyle(.blue)
            if let pulse = $0.pulse {
                LineMark(x: .value("日期", $0.date), y: .value("脉搏", pulse))
                    .foregroundStyle(.green)
            }
        }
        .frame(height: 140)
#else
        Text("暂无图表")
#endif
    }
}
