import XCTest

/// Keeps Russian out of code: comments are English everywhere, and app string literals are
/// localized through the String Catalog. Domain data that must contain Cyrillic sits in
/// `l10n:data` regions (`// l10n:data-begin` ... `// l10n:data-end`) or on a line ending with
/// `// l10n:data`.
final class SourceHygieneTests: XCTestCase {
    // MARK: Lexer

    struct Span: Equatable {
        enum Kind { case comment, literal }
        let kind: Kind
        let text: String
        let line: Int
    }

    /// A small Swift lexer: comments (`//`, `///`, nested `/* */`) and string literals
    /// (`"…"`, `"""…"""`, raw `#"…"#`, interpolation `\( … )` with nested literals).
    struct Lexer {
        private let s: [Unicode.Scalar]
        private var i = 0
        private var line = 1
        private(set) var spans: [Span] = []

        init(_ source: String) { s = Array(source.unicodeScalars) }

        static func spans(of source: String) -> [Span] {
            var lexer = Lexer(source)
            lexer.code(untilCloseParen: false)
            return lexer.spans
        }

        private func at(_ index: Int) -> Unicode.Scalar? { index < s.count ? s[index] : nil }

        private func matches(_ text: String, at index: Int) -> Bool {
            let scalars = Array(text.unicodeScalars)
            guard index + scalars.count <= s.count else { return false }
            return Array(s[index..<index + scalars.count]) == scalars
        }

        private mutating func code(untilCloseParen: Bool) {
            var depth = 0
            while let c = at(i) {
                if c == "\n" { line += 1; i += 1; continue }
                if c == "/", at(i + 1) == "/" { lineComment(); continue }
                if c == "/", at(i + 1) == "*" { blockComment(); continue }
                if c == "#" || c == "\"" {
                    var hashes = 0
                    var j = i
                    while at(j) == "#" { hashes += 1; j += 1 }
                    if at(j) == "\"" { i = j; string(hashes: hashes); continue }
                    i += 1
                    continue
                }
                if untilCloseParen {
                    if c == "(" { depth += 1 }
                    if c == ")" {
                        if depth == 0 { i += 1; return }
                        depth -= 1
                    }
                }
                i += 1
            }
        }

        private mutating func lineComment() {
            let start = i
            while let c = at(i), c != "\n" { i += 1 }
            spans.append(Span(kind: .comment, text: String(String.UnicodeScalarView(s[start..<i])), line: line))
        }

        private mutating func blockComment() {
            let start = i
            let startLine = line
            var depth = 0
            while i < s.count {
                if s[i] == "/", at(i + 1) == "*" { depth += 1; i += 2; continue }
                if s[i] == "*", at(i + 1) == "/" {
                    depth -= 1
                    i += 2
                    if depth == 0 { break }
                    continue
                }
                if s[i] == "\n" { line += 1 }
                i += 1
            }
            spans.append(Span(kind: .comment, text: String(String.UnicodeScalarView(s[start..<min(i, s.count)])), line: startLine))
        }

        /// `i` is at the opening quote (after any `#`s).
        private mutating func string(hashes: Int) {
            let multiline = matches("\"\"\"", at: i)
            let quotes = multiline ? "\"\"\"" : "\""
            let terminator = quotes + String(repeating: "#", count: hashes)
            let escape = "\\" + String(repeating: "#", count: hashes)
            i += quotes.unicodeScalars.count
            let startLine = line
            var body = String.UnicodeScalarView()
            while i < s.count {
                if matches(terminator, at: i) { i += terminator.unicodeScalars.count; break }
                if matches(escape, at: i) {
                    i += escape.unicodeScalars.count
                    if at(i) == "(" {
                        i += 1
                        code(untilCloseParen: true)
                    } else if i < s.count {
                        // Keep the escape as written (backslash plus the escaped character).
                        body.append("\\")
                        if s[i] == "\n" { line += 1 }
                        body.append(s[i])
                        i += 1
                    }
                    continue
                }
                if !multiline, s[i] == "\n" { break } // unterminated: recover at the line end
                if s[i] == "\n" { line += 1 }
                body.append(s[i])
                i += 1
            }
            spans.append(Span(kind: .literal, text: String(body), line: startLine))
        }
    }

    static func hasCyrillic(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0400...0x052F).contains($0.value) }
    }

    // MARK: Lexer self-tests

    func testLexerNestedLiteralInInterpolation() {
        let spans = Lexer.spans(of: #"let x = "a \(b ?? "Перевод") c""#)
        XCTAssertEqual(spans, [
            Span(kind: .literal, text: "Перевод", line: 1),
            Span(kind: .literal, text: "a  c", line: 1)
        ])
    }

    func testLexerUrlWithSlashesAndCyrillicIsNotAComment() {
        let spans = Lexer.spans(of: #"f("https://x/?q=кот") // trailing"#)
        XCTAssertEqual(spans, [
            Span(kind: .literal, text: "https://x/?q=кот", line: 1),
            Span(kind: .comment, text: "// trailing", line: 1)
        ])
    }

    func testLexerRawStringContainingQuote() {
        let spans = Lexer.spans(of: ##"let x = #"say "кот" // no"# // c"##)
        XCTAssertEqual(spans, [
            Span(kind: .literal, text: #"say "кот" // no"#, line: 1),
            Span(kind: .comment, text: "// c", line: 1)
        ])
    }

    func testLexerMultilineStringContainingSlashes() {
        let source = "let x = \"\"\"\nhttp://a // b\n\"\"\"\n// after"
        let spans = Lexer.spans(of: source)
        XCTAssertEqual(spans, [
            Span(kind: .literal, text: "\nhttp://a // b\n", line: 1),
            Span(kind: .comment, text: "// after", line: 4)
        ])
    }

    func testLexerNestedBlockComment() {
        let source = "a /* x /* y */ still */ b \"s\""
        let spans = Lexer.spans(of: source)
        XCTAssertEqual(spans, [
            Span(kind: .comment, text: "/* x /* y */ still */", line: 1),
            Span(kind: .literal, text: "s", line: 1)
        ])
    }

    func testLexerEscapedQuote() {
        let spans = Lexer.spans(of: #"let x = "a \" // b" // c"#)
        XCTAssertEqual(spans, [
            Span(kind: .literal, text: #"a \" // b"#, line: 1),
            Span(kind: .comment, text: "// c", line: 1)
        ])
    }

    // MARK: Source rules

    private struct SourceFile {
        let path: String
        let spans: [Span]
        let lines: [String]
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func swiftFiles(in directory: String) throws -> [SourceFile] {
        let root = Self.repoRoot.appendingPathComponent(directory)
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            XCTFail("Cannot read \(root.path)")
            return []
        }
        var files: [SourceFile] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            files.append(SourceFile(path: "\(directory)/" + url.path.replacingOccurrences(of: root.path + "/", with: ""),
                                    spans: Lexer.spans(of: text),
                                    lines: text.components(separatedBy: "\n")))
        }
        XCTAssertFalse(files.isEmpty, "No Swift files under \(directory)")
        return files.sorted { $0.path < $1.path }
    }

    func testNoCyrillicInComments() throws {
        var failures: [String] = []
        for directory in ["MojSlownik", "MojSlownikTests", "MojSlownikUITests"] {
            for file in try swiftFiles(in: directory) {
                for span in file.spans where span.kind == .comment && Self.hasCyrillic(span.text) {
                    failures.append("\(file.path):\(span.line)")
                }
            }
        }
        XCTAssertEqual(failures, [], "Cyrillic in comments (write comments in English)")
    }

    /// Lines covered by `l10n:data-begin/end` regions, plus marker problems.
    private func dataLines(of file: SourceFile) -> (lines: Set<Int>, problems: [String]) {
        var covered = Set<Int>()
        var problems: [String] = []
        var open: Int?
        for span in file.spans where span.kind == .comment {
            if span.text.contains("l10n:data-begin") {
                if open != nil { problems.append("\(file.path):\(span.line) nested l10n:data-begin") }
                open = span.line
            } else if span.text.contains("l10n:data-end") {
                guard let begin = open else {
                    problems.append("\(file.path):\(span.line) l10n:data-end without begin")
                    continue
                }
                covered.formUnion(begin...span.line)
                let region = file.lines[(begin - 1)..<min(span.line, file.lines.count)]
                if !region.contains(where: Self.hasCyrillic) {
                    problems.append("\(file.path):\(begin) l10n:data region without Cyrillic")
                }
                open = nil
            } else if span.text.contains("l10n:data") {
                covered.insert(span.line)
            }
        }
        if let begin = open { problems.append("\(file.path):\(begin) l10n:data-begin without end") }
        return (covered, problems)
    }

    func testNoCyrillicInAppStringLiteralsOutsideDataRegions() throws {
        var failures: [String] = []
        var markerProblems: [String] = []
        for file in try swiftFiles(in: "MojSlownik") {
            let data = dataLines(of: file)
            markerProblems += data.problems
            for span in file.spans where span.kind == .literal && Self.hasCyrillic(span.text) {
                // A literal's span starts on its first line; a multi-line one is covered when
                // that first line is.
                if !data.lines.contains(span.line) { failures.append("\(file.path):\(span.line)") }
            }
        }
        XCTAssertEqual(markerProblems, [], "Unbalanced or empty l10n:data markers")
        XCTAssertEqual(failures, [], "Cyrillic string literal in the app: use the String Catalog or an l10n:data region")
    }

    /// App code reaches swift-fsrs only through `FSRSScheduler`; tests only through `FSRSSchedulerTests`.
    func testOnlyTheSchedulerWrapperImportsFSRS() throws {
        let marker = "import FSRS"
        func importers(in directory: String) throws -> [String] {
            try swiftFiles(in: directory)
                .filter { $0.lines.contains { $0.trimmingCharacters(in: .whitespaces) == marker } }
                .map(\.path)
        }
        XCTAssertEqual(try importers(in: "MojSlownik"), ["MojSlownik/Services/Practice/FSRSScheduler.swift"])
        XCTAssertEqual(try importers(in: "MojSlownikTests"), ["MojSlownikTests/FSRSSchedulerTests.swift"])
        XCTAssertEqual(try importers(in: "MojSlownikUITests"), [])
    }

    func testMarkerRulesOnSamples() {
        let ok = SourceFile(path: "ok", spans: Lexer.spans(of: "// l10n:data-begin\nlet a = \"кот\"\n// l10n:data-end\n"),
                            lines: ["// l10n:data-begin", "let a = \"кот\"", "// l10n:data-end", ""])
        XCTAssertEqual(dataLines(of: ok).problems, [])
        XCTAssertEqual(dataLines(of: ok).lines, [1, 2, 3])
        let empty = SourceFile(path: "e", spans: Lexer.spans(of: "// l10n:data-begin\nlet a = 1\n// l10n:data-end\n"),
                               lines: ["// l10n:data-begin", "let a = 1", "// l10n:data-end", ""])
        XCTAssertEqual(dataLines(of: empty).problems.count, 1)
        let nested = SourceFile(path: "n", spans: Lexer.spans(of: "// l10n:data-begin\n// l10n:data-begin\n"),
                                lines: ["", "", ""])
        XCTAssertFalse(dataLines(of: nested).problems.isEmpty)
    }
}
