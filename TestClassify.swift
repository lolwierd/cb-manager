import Foundation

enum Kind: String {
    case all = "All"
    case text = "Text"
    case link = "Link"
    case code = "Code"
    case path = "Path"
    case image = "Image"
}

func classify(_ text: String) -> Kind {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

    if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
        return .link
    }

    if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") {
        return .path
    }

    let codeMarkers = ["=>", "func ", "const ", "#!/", "import ", "class ", "let ", "SELECT "]
    let codeSymbols = ["{", "}"]
    let markerCount = codeMarkers.count(where: { trimmed.contains($0) })
    let symbolCount = codeSymbols.count(where: { trimmed.contains($0) })

    if markerCount > 0 && (trimmed.contains("\n") || symbolCount > 0) {
        return .code
    }
    if symbolCount == 2 {
        return .code
    }

    return .text
}

let testCases: [(String, Kind)] = [
    ("https://google.com", .link),
    ("/usr/bin/local", .path),
    ("func foo() { return 1 }", .code),
    ("let x = 1", .code), // Expectation: Code
    ("const y = 2", .code), // Expectation: Code
    ("import Foundation", .code), // Expectation: Code
    ("Hello world", .text),
    ("Hello\nWorld", .text),
    ("I have a class tomorrow", .text),
    ("I have a class\ntomorrow", .text), // Expectation: Text (but might fail)
    ("let us go\nto the park", .text), // Expectation: Text
    ("SELECT * FROM users", .code),
    ("{\"key\": \"value\"}", .code)
]

print("Running tests...")
var failed = false
for (input, expected) in testCases {
    let result = classify(input)
    if result != expected {
        print("FAIL: Input: '\(input.replacingOccurrences(of: "\n", with: "\n"))' Expected: \(expected) Got: \(result)")
        failed = true
    } else {
        print("PASS: '\(input.replacingOccurrences(of: "\n", with: "\n"))' -> \(result)")
    }
}
