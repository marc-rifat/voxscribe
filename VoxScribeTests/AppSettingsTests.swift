import XCTest
@testable import VoxScribe

final class AppSettingsTests: XCTestCase {
    private var settings: AppSettings!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "com.voxscribe.tests")!
        defaults.removePersistentDomain(forName: "com.voxscribe.tests")
        settings = AppSettings(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "com.voxscribe.tests")
        super.tearDown()
    }

    func testDefaultHistoryLimit() {
        XCTAssertEqual(settings.historyLimit, 50)
    }

    func testSetHistoryLimit() {
        settings.historyLimit = 100
        XCTAssertEqual(settings.historyLimit, 100)
        XCTAssertEqual(defaults.integer(forKey: "historyLimit"), 100)
    }

    func testDefaultLaunchAtLogin() {
        XCTAssertFalse(settings.launchAtLogin)
    }

    func testSetLaunchAtLogin() {
        settings.launchAtLogin = true
        XCTAssertTrue(settings.launchAtLogin)
    }

    func testDefaultSelectedModel() {
        XCTAssertEqual(settings.selectedModelName, "tiny")
    }

    func testSetSelectedModel() {
        settings.selectedModelName = "base.en"
        XCTAssertEqual(settings.selectedModelName, "base.en")
    }

    func testDefaultAudioInputDeviceID() {
        XCTAssertNil(settings.audioInputDeviceID)
    }

    func testSetAudioInputDeviceID() {
        settings.audioInputDeviceID = "BuiltInMic:42"
        XCTAssertEqual(settings.audioInputDeviceID, "BuiltInMic:42")
    }

    func testDefaultHotkeyKeyCode() {
        XCTAssertNil(settings.hotkeyKeyCode)
    }

    func testSetHotkey() {
        settings.hotkeyKeyCode = 49
        settings.hotkeyModifierFlags = 256
        XCTAssertEqual(settings.hotkeyKeyCode, 49)
        XCTAssertEqual(settings.hotkeyModifierFlags, 256)
    }
}
