import XCTest

final class BPHealthUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    func testLaunchShowsPrimaryNavigation() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["添加血压记录"].waitForExistence(timeout: 5))
    }

    func testAddEditDeleteReadingFlow() {
        let add = app.buttons["添加血压记录"]
        guard add.waitForExistence(timeout: 5) else { return XCTFail("找不到添加记录入口") }
        add.tap()
        let systolic = app.textFields["收缩压"]
        let diastolic = app.textFields["舒张压"]
        guard systolic.waitForExistence(timeout: 5), diastolic.waitForExistence(timeout: 5) else { return XCTFail("找不到血压输入框") }
        systolic.tap(); systolic.typeText("120")
        diastolic.tap(); diastolic.typeText("80")
        app.buttons["保存"].tap()
        let recordsTab = app.tabBars.buttons["记录"]
        XCTAssertTrue(recordsTab.waitForExistence(timeout: 5))
        recordsTab.tap()
        let row = app.otherElements["reading-row"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.navigationBars["编辑记录"].waitForExistence(timeout: 5))
        let editedNote = app.textFields["备注（可选）"]
        XCTAssertTrue(editedNote.waitForExistence(timeout: 5))
        editedNote.tap()
        editedNote.typeText("已编辑")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.otherElements["reading-row"].waitForExistence(timeout: 5))
        row.swipeLeft()
        let delete = app.buttons["删除"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()
        // 上一步点掉的是左滑露出的「删除」。确认框里还有一个同名按钮，必须把范围收进
        // sheets（confirmationDialog 在 iPhone 上就是 action sheet）才是要点的那个。
        // 注意 XCUIElement 没有 lastMatch，别用「取最后一个匹配项」那种写法。
        let confirmDelete = app.sheets.buttons["删除"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 3))
        confirmDelete.tap()
        XCTAssertFalse(app.otherElements["reading-row"].waitForExistence(timeout: 2))
    }

    func testAddFormSupportsDatePickerAndFastingToggle() {
        let add = app.buttons["添加血压记录"]
        guard add.waitForExistence(timeout: 5) else { return XCTFail("找不到添加记录入口") }
        add.tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        let fasting = app.switches["空腹测量"]
        XCTAssertTrue(fasting.waitForExistence(timeout: 5))
        fasting.tap()
        XCTAssertEqual(fasting.value as? String, "1")
        app.buttons["取消"].tap()
    }

    func testTrendsAdviceAndExportNavigation() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        let trends = app.tabBars.buttons["趋势"]
        XCTAssertTrue(trends.waitForExistence(timeout: 5))
        trends.tap()
        XCTAssertTrue(app.navigationBars["趋势"].waitForExistence(timeout: 5))
        let thirtyDays = app.buttons["30天"]
        XCTAssertTrue(thirtyDays.waitForExistence(timeout: 5))
        thirtyDays.tap()
        let advice = app.tabBars.buttons["建议"]
        XCTAssertTrue(advice.waitForExistence(timeout: 5))
        advice.tap()
        XCTAssertTrue(app.navigationBars["饮食与健康建议"].waitForExistence(timeout: 5))
        let profile = app.tabBars.buttons["我的"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        profile.tap()
        let export = app.staticTexts["导出数据"]
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        export.tap()
        XCTAssertTrue(app.buttons["导出 CSV"].waitForExistence(timeout: 5))
    }

    func testSettingsAndDisclaimerAreReachable() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        let profileTab = app.tabBars.buttons["我的"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()
        let settings = app.staticTexts["设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["血压指南"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["开启每日提醒"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["删除全部本地数据"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["隐私与免责声明"].waitForExistence(timeout: 5))
        app.staticTexts["隐私与免责声明"].tap()
        XCTAssertTrue(app.staticTexts["本应用不能替代医生诊断，如有不适请及时就医。"].waitForExistence(timeout: 5))
    }

    func testProfileSpecialPopulationFieldsAreVisible() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        let profileTab = app.tabBars.buttons["我的"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()
        XCTAssertTrue(app.textFields["年龄（可选）"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["填写出生日期"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["已怀孕"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["肾病"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["糖尿病"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["心脏病"].waitForExistence(timeout: 5))
    }
}
