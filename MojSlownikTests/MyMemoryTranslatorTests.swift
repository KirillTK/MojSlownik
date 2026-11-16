import XCTest
@testable import MojSlownik

final class MyMemoryTranslatorTests: XCTestCase {
    private let plRu = TranslationPair(source: .polish, target: .russian)

    private func json(_ text: String) -> Data { Data(text.utf8) }

    private let warning = "MYMEMORY WARNING: YOU USED ALL AVAILABLE FREE TRANSLATIONS FOR TODAY."

    func testBestTranslationThrowsOnNon200ResponseStatus() {
        for status in ["429", "\"403\""] {
            let data = json(#"{"responseStatus":\#(status),"responseData":{"translatedText":"замок"}}"#)
            XCTAssertThrowsError(try MyMemoryTranslator.bestTranslation(from: data, sourceText: "zamek", pair: plRu)) {
                XCTAssertEqual($0 as? TranslationError, .badResponse)
            }
        }
    }

    func testBestTranslationSkipsQuotaWarningAndUsesValidMatch() throws {
        let data = json("""
        {"responseStatus":200,"responseData":{"translatedText":"\(warning)"},
         "matches":[{"segment":"zamek","translation":"замок","match":1}]}
        """)
        XCTAssertEqual(try MyMemoryTranslator.bestTranslation(from: data, sourceText: "zamek", pair: plRu), "замок")
    }

    func testBestTranslationPrefersValidMainResponse() throws {
        let data = json("""
        {"responseStatus":200,"responseData":{"translatedText":"замок"},
         "matches":[{"segment":"zamek","translation":"застёжка","match":0.9}]}
        """)
        XCTAssertEqual(try MyMemoryTranslator.bestTranslation(from: data, sourceText: "zamek", pair: plRu), "замок")
    }

    func testBestTranslationMapsErrorPayloadsToBadResponse() {
        let bodies = [
            #"{"responseStatus":"403","responseData":null,"responseDetails":"INVALID"}"#,
            #"{"responseStatus":429}"#,
            "not json",
            "[]",
        ]
        for body in bodies {
            XCTAssertThrowsError(try MyMemoryTranslator.bestTranslation(from: json(body), sourceText: "zamek", pair: plRu), body) {
                XCTAssertEqual($0 as? TranslationError, .badResponse, body)
            }
            XCTAssertTrue(TranslationAlternatives.parseMyMemory(json(body), sourceText: "zamek").isEmpty, body)
        }
    }

    func testBestTranslationThrowsEmptyWhenNothingValid() {
        let data = json(#"{"responseStatus":200,"responseData":{"translatedText":"zamek"}}"#)
        XCTAssertThrowsError(try MyMemoryTranslator.bestTranslation(from: data, sourceText: "zamek", pair: plRu)) {
            XCTAssertEqual($0 as? TranslationError, .emptyResult)
        }
    }
}
