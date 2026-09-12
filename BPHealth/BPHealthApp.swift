import SwiftUI
import SwiftData

@main @MainActor struct BPHealthApp: App {
    private let container: ModelContainer?
    private let dependencies = AppContainer()
    @StateObject private var store: BPUIStore
    init() {
        let uiTesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        let configuration = ModelConfiguration(isStoredInMemoryOnly: uiTesting)
        let modelContainer = try? ModelContainer(for: BloodPressureReading.self, UserProfile.self, configurations: configuration)
        container = modelContainer
        let models: [BloodPressureReading]
        var loadFailed = false
        if let modelContainer {
            let repository = ReadingRepository(context: modelContainer.mainContext)
            do {
                models = try repository.fetch()
            } catch {
                models = []
                loadFailed = true
            }
        } else {
            models = []
        }
        let initialStore = BPUIStore(readings: models.map { BPUIReading(model: $0) }, context: modelContainer?.mainContext, dependencies: dependencies)
        if loadFailed { initialStore.persistenceMessage = "本地记录读取失败，当前显示为空列表，请稍后重试。" }
        initialStore.loadProfile()
        _store = StateObject(wrappedValue: initialStore)
    }
    var body: some Scene {
        WindowGroup {
            if let container {
                BPHealthRootView(store: store).modelContainer(container)
            } else {
                Text("本地数据暂不可用，请重启应用")
            }
        }
    }
}
