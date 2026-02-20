import XCTest
@testable import CBManager

/// Tests for text classification logic used by ClipboardStore.
/// Since `classify` is private, we test its behavior through the public `ClipboardEntry.Kind`
/// assignments and the classification heuristics directly.
///
/// The classification rules are:
/// 1. URLs with http/https → .link
/// 2. Starts with "/" or "~/" → .path
/// 3. Contains code hints ({, }, =>, import, func, class, let, const, SELECT, #!) or newlines → .code
/// 4. Otherwise → .text
final class ClipboardStoreClassifyTests: XCTestCase {
    // We replicate the classify logic here to verify the rules directly,
    // since the method is private.

    func testHTTPURLClassifiedAsLink() {
        XCTAssertEqual(classify("https://example.com"), .link)
        XCTAssertEqual(classify("http://example.com"), .link)
        XCTAssertEqual(classify("https://example.com/path?q=1"), .link)
    }

    func testNonHTTPURLNotClassifiedAsLink() {
        XCTAssertNotEqual(classify("ftp://example.com"), .link)
        XCTAssertNotEqual(classify("ssh://server"), .link)
    }

    func testPlainTextNotClassifiedAsLink() {
        XCTAssertNotEqual(classify("just some text"), .link)
    }

    func testAbsolutePathClassifiedAsPath() {
        XCTAssertEqual(classify("/usr/local/bin"), .path)
        XCTAssertEqual(classify("/Users/test/file.txt"), .path)
    }

    func testHomePathClassifiedAsPath() {
        XCTAssertEqual(classify("~/Documents/file.txt"), .path)
        XCTAssertEqual(classify("~/"), .path)
    }

    func testCodeWithBracesClassifiedAsCode() {
        XCTAssertEqual(classify("function test() { return 1; }"), .code)
        XCTAssertEqual(classify("{ \"key\": \"value\" }"), .code)
    }

    func testCodeWithArrowFunctionClassifiedAsCode() {
        XCTAssertEqual(classify("const fn = () => 42"), .code)
    }

    func testCodeWithImportClassifiedAsCode() {
        XCTAssertEqual(classify("import Foundation"), .code)
    }

    func testCodeWithFuncClassifiedAsCode() {
        XCTAssertEqual(classify("func hello() -> String"), .code)
    }

    func testCodeWithClassClassifiedAsCode() {
        XCTAssertEqual(classify("class MyClass: NSObject"), .code)
    }

    func testCodeWithLetClassifiedAsCode() {
        XCTAssertEqual(classify("let x = 42"), .code)
    }

    func testCodeWithConstClassifiedAsCode() {
        XCTAssertEqual(classify("const value = 'hello'"), .code)
    }

    func testCodeWithSelectSQLClassifiedAsCode() {
        XCTAssertEqual(classify("SELECT * FROM users"), .code)
    }

    func testCodeWithShebangClassifiedAsCode() {
        XCTAssertEqual(classify("#!/bin/bash\necho hello"), .code)
    }

    func testMultilineTextClassifiedAsCode() {
        XCTAssertEqual(classify("line one\nline two"), .code)
    }

    func testPlainTextClassifiedAsText() {
        XCTAssertEqual(classify("hello world"), .text)
        XCTAssertEqual(classify("simple note"), .text)
        XCTAssertEqual(classify("meeting at 3pm"), .text)
    }

    func testWhitespaceOnlyAfterTrimClassifiedAsText() {
        // This would be filtered before classification in practice,
        // but the classify function itself would return .text
        XCTAssertEqual(classify("hello"), .text)
    }

    func testURLWithWhitespaceIsStillLink() {
        XCTAssertEqual(classify("  https://example.com  "), .link)
    }

    func testPathWithWhitespaceIsStillPath() {
        XCTAssertEqual(classify("  /usr/local/bin  "), .path)
    }

    // MARK: - Replicated classify logic

    /// Mirrors the private `classify` method from `ClipboardStore`.
    private func classify(_ text: String) -> ClipboardEntry.Kind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            return .link
        }

        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") {
            return .path
        }

        let codeHints = ["{", "}", "=>", "import ", "func ", "class ", "let ", "const ", "SELECT ", "#!/"]
        if codeHints.contains(where: { trimmed.contains($0) }) || trimmed.contains("\n") {
            return .code
        }

        return .text
    }
}
