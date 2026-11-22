import XCTest
@testable import MojSlownik

final class LocalizationRuntimeTests: XCTestCase {
    private typealias Support = LocalizationTestSupport

    func testHostRunsInEnglishAndBundleHasBothLocalizations() {
        XCTAssertEqual(Bundle.main.preferredLocalizations.first, "en")
        XCTAssertTrue(Set(Bundle.main.localizations).isSuperset(of: ["en", "ru"]))
        XCTAssertEqual(Bundle.main.developmentLocalization, "en")
    }

    func testPreferredLocalizationRule() {
        let available = ["en", "ru"]
        XCTAssertEqual(Bundle.preferredLocalizations(from: available, forPreferences: ["ru-RU"]).first, "ru")
        XCTAssertEqual(Bundle.preferredLocalizations(from: available, forPreferences: ["de", "ru"]).first, "ru")
        // No dedicated fallback assertion through this API for ["de"]: the E2E German launch covers it.
    }

    func testRussianWordPluralForms() {
        let expected: [(Int, String)] = [(0, "0 слов"), (1, "1 слово"), (3, "3 слова"), (5, "5 слов"),
                                         (11, "11 слов"), (12, "12 слов"), (21, "21 слово"), (248, "248 слов")]
        for (n, text) in expected {
            XCTAssertEqual(Support.ruWords(n), text)
        }
    }

    func testRussianFolderPluralForms() {
        XCTAssertEqual(Support.ruFolders(1), "1 папка")
        XCTAssertEqual(Support.ruFolders(4), "4 папки")
        XCTAssertEqual(Support.ruFolders(5), "5 папок")
    }

    func testEnglishPluralForms() {
        XCTAssertEqual(WorkspaceLabels.wordCount(1), "1 word")
        XCTAssertEqual(WorkspaceLabels.wordCount(5), "5 words")
        XCTAssertEqual(WorkspaceLabels.folderCount(1), "1 folder")
        XCTAssertEqual(WorkspaceLabels.folderCount(2), "2 folders")
    }

    func testRussianLanguageNameForms() {
        XCTAssertEqual(Support.ruLanguageNames.map(\.code), Language.all.map(\.code))
        for entry in Support.ruLanguageNames {
            XCTAssertEqual(entry.forms.count, Support.nameForms.count)
            for (form, expected) in zip(Support.nameForms, entry.forms) {
                XCTAssertEqual(Support.ru("language.\(entry.code).\(form)"), expected, "\(entry.code).\(form)")
            }
        }
    }

    func testEnglishLanguageNames() {
        let english = ["pl": "Polish", "ru": "Russian", "uk": "Ukrainian", "en": "English", "de": "German",
                       "fr": "French", "es": "Spanish", "it": "Italian", "cs": "Czech", "pt": "Portuguese"]
        XCTAssertEqual(Set(english.keys), Set(Language.all.map(\.code)))
        for (code, name) in english {
            let names = LanguageNames.of(code)
            XCTAssertEqual(names.name, name)
            XCTAssertEqual(names.inline, name)
            XCTAssertEqual(names.inputOption, name)
            XCTAssertEqual(names.genitive, name)
            XCTAssertEqual(names.adverb, "in \(name)")
            XCTAssertEqual(names.wordPlaceholder, "\(name) word")
        }
    }

    func testUnknownCodeFallsBackToTheCode() {
        XCTAssertEqual(LanguageNames.of("xx").name, "xx")
        XCTAssertEqual(LanguageNames.of("xx").adverb, "xx")
    }
}
