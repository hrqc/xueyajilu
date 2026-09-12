import XCTest
import SwiftUI
import UIKit
#if SWIFT_PACKAGE
@testable import BPHealthCore
#else
@testable import BPHealth
#endif

/// Exercises page composition in the unit-test target so coverage reflects the
/// production SwiftUI composition layer, while interaction behavior remains in
/// BPHealthUITests.
@MainActor
final class BPHealthViewCoverageTests: XCTestCase {
    func testAllHealthManagementPagesCanBeHosted() {
        let reading = BPUIReading(date: .now, systolic: 128, diastolic: 82, pulse: 72, isFasting: false, note: "页面覆盖")
        let store = BPUIStore(readings: [reading])
        store.profile.ageOverride = 68
        store.profile.height = 168
        store.profile.weight = 72
        store.profile.chronicConditions = ["肾病"]
        let showingAdd = Binding.constant(false)
        let pages: [AnyView] = [
            AnyView(BPHealthRootView(store: store)),
            AnyView(DashboardView(store: store, showingAdd: showingAdd)),
            AnyView(AddEditReadingView(store: store, editing: reading)),
            AnyView(HistoryView(store: store)),
            AnyView(TrendsView(store: store)),
            AnyView(AdviceView(store: store)),
            AnyView(ProfileView(store: store)),
            AnyView(SettingsView(store: store)),
            AnyView(ExportView(store: store)),
            AnyView(PrivacyDisclaimerView())
        ]

        // Access each opaque body explicitly. UIHostingController alone may
        // defer SwiftUI result-builder evaluation until a run-loop layout pass.
        _ = BPHealthRootView(store: store).body
        _ = DashboardView(store: store, showingAdd: showingAdd).body
        _ = AddEditReadingView(store: store, editing: reading).body
        _ = HistoryView(store: store).body
        _ = TrendsView(store: store).body
        _ = AdviceView(store: store).body
        _ = ProfileView(store: store).body
        _ = SettingsView(store: store).body
        _ = ExportView(store: store).body
        _ = PrivacyDisclaimerView().body

        for page in pages {
            let host = UIHostingController(rootView: page)
            host.loadViewIfNeeded()
            XCTAssertNotNil(host.view)
        }
    }

    func testEmptyAndAlternatePageStatesAreSafe() {
        let store = BPUIStore()
        store.reminderEnabled = true
        store.profile.birthDate = Calendar.current.date(byAdding: .year, value: -45, to: .now)
        store.persistenceMessage = "模拟持久化错误"
        let showingAdd = Binding.constant(true)

        _ = BPHealthRootView(store: store).body
        _ = DashboardView(store: store, showingAdd: showingAdd).body
        _ = HistoryView(store: store).body
        _ = TrendsView(store: store).body
        _ = AdviceView(store: store).body
        _ = ProfileView(store: store).body
        _ = SettingsView(store: store).body
        XCTAssertTrue(store.readings.isEmpty)
    }
}
