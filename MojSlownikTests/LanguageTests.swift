import XCTest
@testable import MojSlownik

final class LanguageTests: XCTestCase {
    func testAllEqualsTheSyncSupportedList() {
        XCTAssertEqual(Language.all.map(\.code), LanguageCodes.supported)
    }

    func testOnlyTheGuidedPairsAreSelectable() {
        XCTAssertEqual(Language.studyOrder.map(\.code), ["pl", "en", "de"])
        XCTAssertEqual(Language.translationOrder.map(\.code), ["ru", "uk", "en"])
    }

    func testLegacyPairsStillResolve() {
        for (term, translation) in [("fr", "ru"), ("pl", "cs"), ("es", "pt"), ("ru", "pl")] {
            let pair = LanguagePair(termCode: term, translationCode: translation)
            XCTAssertEqual(pair?.term.code, term)
            XCTAssertEqual(pair?.translation.code, translation)
        }
    }

    func testTableIntegrity() {
        XCTAssertEqual(Set(Language.all.map(\.code)).count, Language.all.count)
        XCTAssertEqual(Set(Language.all.map(\.flag)).count, Language.all.count)
        for language in Language.all {
            XCTAssertFalse(language.localizedName.isEmpty)
            XCTAssertNotEqual(language.localizedName, language.code, "the name is in the catalog")
            XCTAssertFalse(language.endonym.isEmpty)
            XCTAssertFalse(language.speechCode.isEmpty)
            XCTAssertFalse(language.ocrCode.isEmpty)
            XCTAssertEqual(language.googleCode, language.code)
            XCTAssertEqual(language.myMemoryCode, language.code)
            XCTAssertEqual(language.scripts.count, 1)
            XCTAssertEqual(Language(code: language.code), language)
            XCTAssertEqual(language.preservesCase, LanguageCodes.preservesCase(language.code))
        }
        XCTAssertNil(Language(code: "xx"))
    }

    func testPlanTableValues() {
        XCTAssertEqual(Language.english.speechCode, "en-GB")
        XCTAssertEqual(Language.english.ocrCode, "en-US")
        XCTAssertEqual(Language.portuguese.speechCode, "pt-PT")
        XCTAssertEqual(Language.portuguese.ocrCode, "pt-BR")
        XCTAssertNil(Language.czech.appleIdentifier)
        XCTAssertEqual(Language.german.appleIdentifier, "de")
        XCTAssertEqual(Language.polish.scripts, [.latin])
        XCTAssertEqual(Language.ukrainian.scripts, [.cyrillic])
    }

    func testEnglishNameForms() {
        XCTAssertEqual(Language.polish.names.adverb, "in Polish")
        XCTAssertEqual(Language.russian.names.wordPlaceholder, "Russian word")
        XCTAssertEqual(Language.polish.localizedName, Language.polish.names.name)
        for language in Language.all {
            XCTAssertEqual(language.names, LanguageNames.of(language.code))
            XCTAssertTrue(language.names.adverb.hasPrefix("in "), language.code)
        }
    }

    func testStoredFormTrimsAndOnlyGermanKeepsCase() {
        XCTAssertEqual(Language.polish.storedForm("  KOT\n"), "kot")
        XCTAssertEqual(Language.russian.storedForm("Кот"), "кот")
        XCTAssertEqual(Language.german.storedForm(" Das Haus "), "Das Haus")
        XCTAssertEqual(Language.english.storedForm("House"), "house")
    }

    func testDetectSideByScript() {
        let plRu = LanguagePair.polishRussian
        XCTAssertEqual(plRu.detectSide("kot"), .term)
        XCTAssertEqual(plRu.detectSide("кот"), .translation)
        XCTAssertEqual(plRu.detectSide("zażółć"), .term)
        XCTAssertEqual(plRu.detectSide("Wi-Fi роутер"), .translation)
        XCTAssertEqual(plRu.detectSide("USB кабель"), .translation)
        XCTAssertEqual(plRu.detectSide("kabel USB"), .term)
        XCTAssertNil(plRu.detectSide("123 ?"))
        XCTAssertNil(plRu.detectSide(""))
        let deUk = LanguagePair(term: .german, translation: .ukrainian)
        XCTAssertEqual(deUk.detectSide("Haus"), .term)
        XCTAssertEqual(deUk.detectSide("дім"), .translation)
    }

    func testSameScriptPairsCannotDetect() {
        let enPl = LanguagePair(term: .english, translation: .polish)
        XCTAssertTrue(enPl.isSameScript)
        XCTAssertNil(enPl.detectSide("house"))
        let ukRu = LanguagePair(term: .ukrainian, translation: .russian)
        XCTAssertTrue(ukRu.isSameScript)
        XCTAssertNil(ukRu.detectSide("дім"))
        XCTAssertFalse(LanguagePair.polishRussian.isSameScript)
    }

    func testPairSidesAndTranslationDirection() {
        let pair = LanguagePair.polishRussian
        XCTAssertEqual(pair.language(of: .term), .polish)
        XCTAssertEqual(pair.language(of: .translation), .russian)
        XCTAssertEqual(pair.translationPair(from: .term), TranslationPair(source: .polish, target: .russian))
        XCTAssertEqual(pair.translationPair(from: .translation), TranslationPair(source: .russian, target: .polish))
        XCTAssertNil(LanguagePair(termCode: "pl", translationCode: "xx"))
    }

    func testWordEntryMakePlacesInputOnTheSide() {
        XCTAssertEqual(WordEntry.make(input: "kot", translation: "кот", side: .term),
                       WordEntry(term: "kot", translation: "кот", enteredSide: .term))
        XCTAssertEqual(WordEntry.make(input: "кот", translation: "kot", side: .translation),
                       WordEntry(term: "kot", translation: "кот", enteredSide: .translation))
    }
}
