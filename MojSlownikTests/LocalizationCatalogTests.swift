import XCTest

/// Structural checks of the source String Catalogs. Dead and missing keys are the job of
/// scripts/check-localization.sh, not of this test.
final class LocalizationCatalogTests: XCTestCase {
    private typealias JSON = [String: Any]

    private func loadCatalog(_ name: String) throws -> JSON {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MojSlownik").appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? JSON)
    }

    /// Specifier types by position: `%@`, `%lld`, `%1$@`, `%2$lld`; `%%` is ignored.
    private func specifiers(_ text: String) -> [Int: String] {
        let regex = try! NSRegularExpression(pattern: "%(?:(\\d+)\\$)?(@|lld|ld|d|f|lf)")
        var result: [Int: String] = [:]
        var next = 1
        let withoutEscapes = text.replacingOccurrences(of: "%%", with: "")
        let range = NSRange(withoutEscapes.startIndex..., in: withoutEscapes)
        for match in regex.matches(in: withoutEscapes, range: range) {
            let type = String(withoutEscapes[Range(match.range(at: 2), in: withoutEscapes)!])
            if match.range(at: 1).location != NSNotFound {
                result[Int(withoutEscapes[Range(match.range(at: 1), in: withoutEscapes)!])!] = type
            } else {
                result[next] = type
                next += 1
            }
        }
        return result
    }

    private func translatedValue(_ unit: Any?, _ context: String) throws -> String {
        let dict = try XCTUnwrap(unit as? JSON, "\(context): missing stringUnit")
        let stringUnit = try XCTUnwrap(dict["stringUnit"] as? JSON, "\(context): missing stringUnit")
        XCTAssertEqual(stringUnit["state"] as? String, "translated", context)
        let value = try XCTUnwrap(stringUnit["value"] as? String, context)
        XCTAssertFalse(value.isEmpty, context)
        return value
    }

    /// All values of one localization: the plain value, or one per plural category.
    private func values(_ localization: JSON, language: String, key: String,
                        pluralCategories: Set<String>) throws -> (values: [String], isPlural: Bool) {
        let context = "\(key) [\(language)]"
        XCTAssertNil(localization["substitutions"], "\(context): substitutions are not allowed")
        if let variations = localization["variations"] as? JSON {
            let plural = try XCTUnwrap(variations["plural"] as? JSON, "\(context): only plural variations")
            XCTAssertEqual(Set(plural.keys), pluralCategories, "\(context): plural categories")
            return (try plural.map { try translatedValue($0.value, "\(context).\($0.key)") }, true)
        }
        return ([try translatedValue(localization, context)], false)
    }

    func testLocalizableCatalogIsCompleteAndConsistent() throws {
        let catalog = try loadCatalog("Localizable.xcstrings")
        XCTAssertEqual(catalog["sourceLanguage"] as? String, "en")
        let strings = try XCTUnwrap(catalog["strings"] as? JSON)
        XCTAssertFalse(strings.isEmpty)
        for (key, entry) in strings {
            let localizations = try XCTUnwrap((entry as? JSON)?["localizations"] as? JSON, key)
            let en = try XCTUnwrap(localizations["en"] as? JSON, "\(key): missing en")
            let ru = try XCTUnwrap(localizations["ru"] as? JSON, "\(key): missing ru")
            let enValues = try values(en, language: "en", key: key, pluralCategories: ["one", "other"])
            let ruValues = try values(ru, language: "ru", key: key, pluralCategories: ["one", "few", "many", "other"])
            XCTAssertEqual(enValues.isPlural, ruValues.isPlural, "\(key): plural in one language only")
            XCTAssertFalse(key.contains("%#@"), "\(key): substitutions are not allowed")
            let reference = specifiers(enValues.values[0])
            for value in enValues.values + ruValues.values {
                XCTAssertEqual(specifiers(value), reference, "\(key): specifiers differ in '\(value)'")
            }
            if enValues.isPlural {
                XCTAssertEqual(reference.count, 1, "\(key): a plural key has exactly one argument")
                XCTAssertEqual(reference.first?.value, "lld", "\(key): the plural argument is numeric")
            }
            if reference.count > 0 {
                XCTAssertNotNil((entry as? JSON)?["comment"], "\(key): keys with placeholders need a comment")
            }
        }
    }

    func testInfoPlistCatalogHasTheThreeUsageDescriptions() throws {
        let catalog = try loadCatalog("InfoPlist.xcstrings")
        XCTAssertEqual(catalog["sourceLanguage"] as? String, "en")
        let strings = try XCTUnwrap(catalog["strings"] as? JSON)
        XCTAssertEqual(Set(strings.keys), ["NSCameraUsageDescription", "NSMicrophoneUsageDescription",
                                           "NSSpeechRecognitionUsageDescription"])
        for (key, entry) in strings {
            let localizations = try XCTUnwrap((entry as? JSON)?["localizations"] as? JSON, key)
            for language in ["en", "ru"] {
                _ = try translatedValue(localizations[language], "\(key) [\(language)]")
            }
        }
    }
}
