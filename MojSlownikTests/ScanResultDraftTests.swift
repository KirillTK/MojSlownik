import XCTest
@testable import MojSlownik

@MainActor
final class ScanResultDraftTests: XCTestCase {
    private final class TranslatorStub {
        var texts: [String] = []
        var pairs: [TranslationPair] = []
        var requests: [CheckedContinuation<String, Error>] = []

        func translate(_ text: String, pair: TranslationPair) async throws -> String {
            texts.append(text)
            pairs.append(pair)
            return try await withCheckedThrowingContinuation { requests.append($0) }
        }
    }

    private func waitForRequests(_ count: Int, in stub: TranslatorStub) async {
        for _ in 0..<1_000 {
            if stub.requests.count >= count { return }
            await Task.yield()
        }
        XCTFail("Translation did not start")
    }

    func testEditRejectsStaleParagraphAndWordResults() async {
        let stub = TranslatorStub()
        let draft = ScanResultDraft(sourceText: "kot", pair: .polishRussian, debounce: .zero, translate: stub.translate)
        draft.startTranslationIfNeeded()
        await waitForRequests(1, in: stub)

        draft.setSource("pies")
        await waitForRequests(2, in: stub)
        stub.requests[0].resume(returning: "старый текст")
        stub.requests[1].resume(returning: "новый текст")
        await waitForRequests(3, in: stub)
        stub.requests[2].resume(returning: "собака")
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(stub.texts, ["kot", "pies", "pies"])
        XCTAssertEqual(draft.sourceText, "pies")
        XCTAssertEqual(draft.translatedText, "новый текст")
        XCTAssertEqual(draft.translations, ["pies": "собака"])
        XCTAssertNil(draft.translationError)
        XCTAssertFalse(draft.isTranslating)
    }

    func testStaleFailureCannotClearNewRequestLoadingState() async {
        let stub = TranslatorStub()
        let draft = ScanResultDraft(sourceText: "kot", pair: .polishRussian, debounce: .zero, translate: stub.translate)
        draft.startTranslationIfNeeded()
        await waitForRequests(1, in: stub)

        draft.setSource("pies")
        await waitForRequests(2, in: stub)
        XCTAssertTrue(draft.isTranslating)
        stub.requests[0].resume(throwing: NSError(domain: "old", code: 1))
        for _ in 0..<20 { await Task.yield() }

        XCTAssertTrue(draft.isTranslating)
        XCTAssertNil(draft.translationError)
        stub.requests[1].resume(returning: "новый текст")
        await waitForRequests(3, in: stub)
        stub.requests[2].resume(returning: "собака")
    }

    func testPolishAndRussianWordsTranslateToTheOtherSide() async {
        let stub = TranslatorStub()
        let draft = ScanResultDraft(sourceText: "kot кошка", pair: .polishRussian, debounce: .zero,
                                    translate: stub.translate)
        draft.startTranslationIfNeeded()
        // the whole text, then each word
        for _ in 0..<3 {
            await waitForRequests(stub.requests.count + 1, in: stub)
            stub.requests.last?.resume(returning: "x")
        }
        for _ in 0..<20 { await Task.yield() }

        let byText = Dictionary(zip(stub.texts, stub.pairs), uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(byText["kot"], TranslationPair(source: .polish, target: .russian))
        XCTAssertEqual(byText["кошка"], TranslationPair(source: .russian, target: .polish))
    }

    func testSameScriptPairScansTheStudiedLanguage() {
        let draft = ScanResultDraft(sourceText: "house", pair: LanguagePair(term: .english, translation: .polish))
        XCTAssertEqual(draft.side(of: "house"), .term)
        XCTAssertEqual(draft.side(of: "dom"), .term)
    }

    func testUnknownScriptDefaultsToTheStudiedSide() {
        let draft = ScanResultDraft(sourceText: "123", pair: .polishRussian)
        XCTAssertEqual(draft.side(of: "123"), .term)
        XCTAssertEqual(draft.side(of: "кот"), .translation)
    }
}
