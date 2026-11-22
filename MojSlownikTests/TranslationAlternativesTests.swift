import XCTest
@testable import MojSlownik

final class TranslationAlternativesTests: XCTestCase {
    private let german = Language.german
    private let english = Language.english
    private let pl_ru = TranslationPair(source: .polish, target: .russian)
    private let ru_pl = TranslationPair(source: .russian, target: .polish)
    private var de_ru: TranslationPair { TranslationPair(source: german, target: .russian) }
    private var pl_en: TranslationPair { TranslationPair(source: .polish, target: english) }

    private func data(_ s: String) -> Data { Data(s.utf8) }
    private func alt(_ text: String, _ pos: String? = nil) -> TranslationAlternative {
        TranslationAlternative(text: text, partOfSpeech: pos)
    }

    // Google gtx fixture. Live capture was blocked by Google throttling (HTML "Sorry..." page)
    // from the dev network, so this follows the documented gtx shape: t, bd (index 1), at (index 5).
    private let googleZamek = """
    [[["замок","zamek",null,null,10]],
     [["существительное",["замок","застёжка","молния"],[["замок",["zamek"],null,0.5]],"zamek",1],
      ["глагол",["закрыть"],null,"zamek",1]],
     "pl",null,null,
     [["zamek",null,[["замок",1000,true,false,[10]],["застёжка",500,true,false,[10]]],[[0,5]],"zamek",0,0]],
     1,null,[["pl"],null,[1],["pl"]]]
    """

    func testParseGoogleReadsTranslationDictionaryAndAlternatives() {
        let result = TranslationAlternatives.parseGoogle(data(googleZamek))
        XCTAssertEqual(result, [
            alt("замок"),
            alt("замок", "существительное"), alt("застёжка", "существительное"), alt("молния", "существительное"),
            alt("закрыть", "глагол"),
            alt("замок"), alt("застёжка"),
        ])
    }

    func testParseGoogleSkipsMultiSegmentAlternativesAndHandlesNullDictionary() {
        let multi = """
        [[["Dzień dobry","x"]],null,"pl",null,null,
         [["a",null,[["ignored",1]]],["b",null,[["ignored2",1]]]]]
        """
        XCTAssertEqual(TranslationAlternatives.parseGoogle(data(multi)), [alt("Dzień dobry")])
    }

    func testParseGoogleReturnsEmptyForHtmlAndMalformedInput() {
        for body in ["<html><title>Sorry...</title></html>", "{}", "[]", "[null]"] {
            XCTAssertTrue(TranslationAlternatives.parseGoogle(data(body)).isEmpty, body)
        }
    }

    // Real zamek pl->ru response shape from api.mymemory.translated.net (trimmed).
    private func myMemory(status: String = "200", main: String = "замок") -> String {
        """
        {"responseData":{"translatedText":"\(main)","match":1},"responseDetails":"","responseStatus":\(status),
         "matches":[
          {"segment":"Zamek PFP","translation":"Замок PFP","quality":"0","match":0.85},
          {"segment":"Zamek","translation":"Замок","quality":74,"match":0.97},
          {"segment":"zamek","translation":"zamek&#39;s замок","quality":"0","match":1},
          {"segment":"zamek","translation":"застёжка","quality":"0","match":0.5}]}
        """
    }

    func testParseMyMemoryKeepsExactSegmentMatchesSortedByScore() {
        let result = TranslationAlternatives.parseMyMemory(data(myMemory()), sourceText: "zamek")
        XCTAssertEqual(result.map(\.text), ["замок", "zamek's замок", "Замок", "застёжка"])
    }

    func testParseMyMemoryRejectsNon200StatusAsIntOrString() {
        XCTAssertTrue(TranslationAlternatives.parseMyMemory(data(myMemory(status: "429")), sourceText: "zamek").isEmpty)
        XCTAssertTrue(TranslationAlternatives.parseMyMemory(data(myMemory(status: "\"403\"")), sourceText: "zamek").isEmpty)
        XCTAssertFalse(TranslationAlternatives.parseMyMemory(data(myMemory(status: "\"200\"")), sourceText: "zamek").isEmpty)
    }

    func testParseMyMemoryDropsQuotaWarningText() {
        let body = myMemory(main: "MYMEMORY WARNING: YOU USED ALL AVAILABLE FREE TRANSLATIONS FOR TODAY.")
        let result = TranslationAlternatives.parseMyMemory(data(body), sourceText: "zamek")
        XCTAssertEqual(result.map(\.text), ["zamek's замок", "Замок", "застёжка"])
    }

    func testParseMyMemoryReturnsEmptyOnMalformedJSON() {
        XCTAssertTrue(TranslationAlternatives.parseMyMemory(data("oops"), sourceText: "zamek").isEmpty)
    }

    func testIsValidUsesDescriptorScripts() {
        XCTAssertTrue(TranslationAlternatives.isValid("замок", sourceText: "zamek", pair: pl_ru))
        XCTAssertFalse(TranslationAlternatives.isValid("Замок PFP", sourceText: "zamek", pair: pl_ru))
        XCTAssertFalse(TranslationAlternatives.isValid("zamek", sourceText: "zamek", pair: pl_ru))
        XCTAssertTrue(TranslationAlternatives.isValid("zamek", sourceText: "замок", pair: ru_pl))
        XCTAssertFalse(TranslationAlternatives.isValid("замок", sourceText: "замок", pair: ru_pl))
        XCTAssertFalse(TranslationAlternatives.isValid("замок", sourceText: "kot", pair: ru_pl))
        XCTAssertTrue(TranslationAlternatives.isValid("castle", sourceText: "zamek", pair: pl_en))
        XCTAssertFalse(TranslationAlternatives.isValid("zamek", sourceText: "zamek", pair: pl_en))
        XCTAssertTrue(TranslationAlternatives.isValid("замок", sourceText: "Schloss", pair: de_ru))
        XCTAssertFalse(TranslationAlternatives.isValid("Schloss", sourceText: "Schloss", pair: de_ru))
        XCTAssertFalse(TranslationAlternatives.isValid("castle", sourceText: "Schloss", pair: de_ru))
        XCTAssertTrue(TranslationAlternatives.isValid("замок-2", sourceText: "zamek", pair: pl_ru))
        // Letterless candidates (numbers) are accepted unless they echo the source.
        XCTAssertTrue(TranslationAlternatives.isValid("100", sourceText: "sto", pair: pl_ru))
        XCTAssertFalse(TranslationAlternatives.isValid("100", sourceText: "100", pair: pl_ru))
        XCTAssertFalse(TranslationAlternatives.isValid("  ", sourceText: "zamek", pair: pl_ru))
    }

    func testMergeDedupesCaseInsensitivelyExcludesPrimaryAndSourceAndCaps() {
        let groups = [
            [alt("Замок"), alt("замок", "сущ."), alt("застёжка"), alt("zamek"), alt("Замок PFP"), alt("")],
            [alt("ЗАСТЁЖКА", "сущ."), alt("а"), alt("б"), alt("в"), alt("г"), alt("д"), alt("е"), alt("ж")],
        ]
        let result = TranslationAlternatives.merge(primary: "замок", groups: groups, sourceText: "zamek", pair: pl_ru)
        XCTAssertEqual(result.count, 6)
        XCTAssertEqual(result.first, alt("застёжка", "сущ."))
        XCTAssertEqual(result.map(\.text), ["застёжка", "а", "б", "в", "г", "д"])
    }

    func testMergeWorksForNonPolishRussianPair() {
        let group = [alt("замок"), alt("Schloss"), alt("castle")]
        XCTAssertEqual(
            TranslationAlternatives.merge(primary: nil, groups: [group], sourceText: "Schloss", pair: de_ru).map(\.text),
            ["замок"])
        XCTAssertEqual(
            TranslationAlternatives.merge(primary: nil, groups: [group], sourceText: "zamek", pair: pl_en).map(\.text),
            ["Schloss", "castle"])
    }

    func testMergeWithoutPrimaryKeepsAllValidCandidates() {
        let result = TranslationAlternatives.merge(
            primary: nil, groups: [[alt("замок"), alt("застёжка")]], sourceText: "zamek", pair: pl_ru)
        XCTAssertEqual(result.map(\.text), ["замок", "застёжка"])
    }

    func testShouldFetchGate() {
        XCTAssertTrue(TranslationAlternatives.shouldFetch("kot"))
        XCTAssertTrue(TranslationAlternatives.shouldFetch("dzień dobry"))
        XCTAssertTrue(TranslationAlternatives.shouldFetch("a b c d"))
        XCTAssertFalse(TranslationAlternatives.shouldFetch("a b c d e"))
        XCTAssertTrue(TranslationAlternatives.shouldFetch(String(repeating: "a", count: 60)))
        XCTAssertFalse(TranslationAlternatives.shouldFetch(String(repeating: "a", count: 61)))
        XCTAssertFalse(TranslationAlternatives.shouldFetch("a\nb"))
        XCTAssertFalse(TranslationAlternatives.shouldFetch("   "))
    }

    func testGoogleURLUsesDescriptorCodesAndInterfaceLanguage() {
        let url = GoogleWebTranslator.url(for: "a+b", pair: de_ru, dt: ["t", "bd", "at"], interfaceLanguage: "ru")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "sl" }?.value, "de")
        XCTAssertEqual(items.first { $0.name == "tl" }?.value, "ru")
        XCTAssertEqual(items.first { $0.name == "hl" }?.value, "ru")
        XCTAssertEqual(items.filter { $0.name == "dt" }.map(\.value), ["t", "bd", "at"])
        XCTAssertTrue(url.absoluteString.contains("q=a%2Bb"))

        let primary = GoogleWebTranslator.url(for: "kot", pair: pl_ru, dt: ["t"])
        XCTAssertEqual(primary.absoluteString,
                       "https://translate.googleapis.com/translate_a/single?client=gtx&sl=pl&tl=ru&dt=t&q=kot")
    }

    func testMyMemoryURLUsesDescriptorCodes() {
        let url = MyMemoryTranslator.url(for: "Schloss", pair: de_ru, contactEmail: "me@example.com")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "langpair" }?.value, "de|ru")
        XCTAssertNotNil(items.first { $0.name == "de" })
        let noEmail = MyMemoryTranslator.url(for: "Schloss", pair: de_ru, contactEmail: nil)
        XCTAssertFalse(noEmail.absoluteString.contains("de=me"))
    }

    func testEveryLanguageBuildsPairsWithItsCodes() {
        for language in Language.all {
            let pair = TranslationPair(source: language, target: .russian)
            XCTAssertEqual(pair.source.googleCode, language.code)
            XCTAssertEqual(pair.source.myMemoryCode, language.code)
        }
    }

    func testCyrillicPairsAcceptTheirOwnScriptsOnly() {
        let uk_ru = TranslationPair(source: .ukrainian, target: .russian)
        XCTAssertTrue(TranslationAlternatives.isValid("дім", sourceText: "dom", pair: TranslationPair(source: .polish, target: .ukrainian)))
        XCTAssertFalse(TranslationAlternatives.isValid("house", sourceText: "дім", pair: uk_ru))
    }
}
