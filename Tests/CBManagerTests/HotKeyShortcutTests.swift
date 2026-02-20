import XCTest
@testable import CBManager

final class HotKeyShortcutTests: XCTestCase {
    // MARK: - Fallback

    func testFallbackShortcutIsCommandShiftV() {
        let fallback = HotKeyShortcut.fallback
        // kVK_ANSI_V = 9
        XCTAssertEqual(fallback.keyCode, 9)
        XCTAssertTrue(fallback.title.contains("⌘"))
        XCTAssertTrue(fallback.title.contains("⇧"))
        XCTAssertTrue(fallback.title.contains("V"))
    }

    // MARK: - Title rendering

    func testTitleIncludesModifiersAndKeyName() {
        let shortcut = HotKeyShortcut.fallback
        let title = shortcut.title
        // Should contain shift (⇧) and command (⌘) symbols plus "V"
        XCTAssertTrue(title.contains("⇧"), "Expected shift symbol in title: \(title)")
        XCTAssertTrue(title.contains("⌘"), "Expected command symbol in title: \(title)")
        XCTAssertTrue(title.contains("V"), "Expected key name in title: \(title)")
    }

    func testTitleWithControlModifier() {
        // controlKey = 4096 (0x1000)
        let shortcut = HotKeyShortcut(keyCode: 0 /* kVK_ANSI_A */, modifiers: 4096)
        XCTAssertTrue(shortcut.title.contains("⌃"))
        XCTAssertTrue(shortcut.title.contains("A"))
    }

    func testTitleWithOptionModifier() {
        // optionKey = 2048 (0x0800)
        let shortcut = HotKeyShortcut(keyCode: 11 /* kVK_ANSI_B */, modifiers: 2048)
        XCTAssertTrue(shortcut.title.contains("⌥"))
        XCTAssertTrue(shortcut.title.contains("B"))
    }

    func testTitleWithAllModifiers() {
        // cmdKey=256, shiftKey=512, optionKey=2048, controlKey=4096
        let allMods: UInt32 = 256 | 512 | 2048 | 4096
        let shortcut = HotKeyShortcut(keyCode: 0 /* A */, modifiers: allMods)
        let title = shortcut.title
        XCTAssertTrue(title.contains("⌃"))
        XCTAssertTrue(title.contains("⌥"))
        XCTAssertTrue(title.contains("⇧"))
        XCTAssertTrue(title.contains("⌘"))
    }

    func testTitleForNumericKeys() {
        // kVK_ANSI_0 = 29, kVK_ANSI_1 = 18
        let shortcut0 = HotKeyShortcut(keyCode: 29, modifiers: 256) // Cmd+0
        XCTAssertTrue(shortcut0.title.contains("0"))

        let shortcut1 = HotKeyShortcut(keyCode: 18, modifiers: 256) // Cmd+1
        XCTAssertTrue(shortcut1.title.contains("1"))
    }

    func testTitleForSpecialKeys() {
        // kVK_Space = 49
        let space = HotKeyShortcut(keyCode: 49, modifiers: 256)
        XCTAssertTrue(space.title.contains("Space"))

        // kVK_Return = 36
        let ret = HotKeyShortcut(keyCode: 36, modifiers: 256)
        XCTAssertTrue(ret.title.contains("↩"))

        // kVK_Escape = 53
        let esc = HotKeyShortcut(keyCode: 53, modifiers: 256)
        XCTAssertTrue(esc.title.contains("⎋"))

        // kVK_Tab = 48
        let tab = HotKeyShortcut(keyCode: 48, modifiers: 256)
        XCTAssertTrue(tab.title.contains("⇥"))

        // kVK_Delete = 51
        let del = HotKeyShortcut(keyCode: 51, modifiers: 256)
        XCTAssertTrue(del.title.contains("⌫"))
    }

    func testTitleForUnknownKeyCodeShowsKeyPrefix() {
        let shortcut = HotKeyShortcut(keyCode: 999, modifiers: 256)
        XCTAssertTrue(shortcut.title.contains("Key999"))
    }

    // MARK: - isValid

    func testIsValidRequiresCommandOrOptionOrControl() {
        // Command only
        XCTAssertTrue(HotKeyShortcut(keyCode: 0, modifiers: 256).isValid)
        // Option only
        XCTAssertTrue(HotKeyShortcut(keyCode: 0, modifiers: 2048).isValid)
        // Control only
        XCTAssertTrue(HotKeyShortcut(keyCode: 0, modifiers: 4096).isValid)
        // Command + Shift
        XCTAssertTrue(HotKeyShortcut(keyCode: 0, modifiers: 256 | 512).isValid)
    }

    func testIsValidReturnsFalseForNoModifiers() {
        XCTAssertFalse(HotKeyShortcut(keyCode: 0, modifiers: 0).isValid)
    }

    func testIsValidReturnsFalseForShiftOnly() {
        // shiftKey = 512
        XCTAssertFalse(HotKeyShortcut(keyCode: 0, modifiers: 512).isValid)
    }

    // MARK: - Codable roundtrip

    func testCodableRoundtrip() throws {
        let original = HotKeyShortcut(keyCode: 9, modifiers: 256 | 512)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotKeyShortcut.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - Equatable

    func testEquality() {
        let a = HotKeyShortcut(keyCode: 9, modifiers: 256)
        let b = HotKeyShortcut(keyCode: 9, modifiers: 256)
        let c = HotKeyShortcut(keyCode: 10, modifiers: 256)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
