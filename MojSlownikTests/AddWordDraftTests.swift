import XCTest
@testable import MojSlownik

@MainActor
final class AddWordDraftTests: XCTestCase {
    private final class TranslatorStub {
        var texts: [String] = []
        var requests: [CheckedContinuation<String, Error>] = []
        func translate(_ text: String, source: AppLanguage) async throws -> String {
            texts.append(text)
            return try await withCheckedThrowingContinuation { requests.append($0) }
        }
    }

    private final class AlternativesStub {
        var calls: [(text: String, pair: TranslationPair)] = []
        var requests: [CheckedContinuation<[[TranslationAlternative]], Never>] = []
        func fetch(_ text: String, pair: TranslationPair) async -> [[TranslationAlternative]] {
            calls.append((text, pair))
            return await withCheckedContinuation { requests.append($0) }
        }
    }

    private func makeDraft(
        translate: @escaping (String, AppLanguage) async throws -> String,
        alternatives: @escaping (String, TranslationPair) async -> [[TranslationAlternative]] = { _, _ in [] }
    ) -> AddWordDraft {
        AddWordDraft(debounce: .zero, translate: translate, alternatives: alternatives)
    }

    private func settle() async {
        for _ in 0..<30 { await Task.yield() }
    }

    private func waitForAlternatives(_ count: Int, in stub: AlternativesStub) async {
        for _ in 0..<1000 {
            if stub.requests.count >= count { return }
            await Task.yield()
        }
        XCTFail("Alternatives did not start")
    }

    private func alt(_ text: String, _ pos: String? = nil) -> TranslationAlternative {
        TranslationAlternative(text: text, partOfSpeech: pos)
    }

    private func waitForRequests(_ count: Int, in stub: TranslatorStub) async {
        for _ in 0..<1000 {
            if stub.requests.count >= count { return }
            await Task.yield()
        }
        XCTFail("Translation did not start")
    }

    func testIdenticalDictationRestartsPendingTranslationOnlyOnceAndRejectsStaleError() async {
        let stub = TranslatorStub()
        let draft = makeDraft(translate: stub.translate)
        draft.setSource("kot")
        await waitForRequests(1, in: stub)
        draft.beginDictation()
        XCTAssertFalse(draft.isTranslating)
        draft.commitDictation("kot")
        draft.endDictation()
        await waitForRequests(2, in: stub)
        stub.requests[1].resume(returning: "кот")
        for _ in 0..<20 { await Task.yield() }
        stub.requests[0].resume(throwing: NSError(domain: "old request", code: 1))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(stub.texts, ["kot", "kot"])
        XCTAssertEqual(draft.translatedText, "кот")
        XCTAssertNil(draft.translationError)
        XCTAssertFalse(draft.isTranslating)
    }

    func testChangedDictationSchedulesOnceAndRejectsStaleSuccess() async {
        let stub = TranslatorStub()
        let draft = makeDraft(translate: stub.translate)
        draft.setSource("kot")
        await waitForRequests(1, in: stub)
        draft.beginDictation()
        draft.commitDictation("pies")
        draft.endDictation()
        await waitForRequests(2, in: stub)
        stub.requests[0].resume(returning: "кот")
        stub.requests[1].resume(returning: "собака")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(stub.texts, ["kot", "pies"])
        XCTAssertEqual(draft.translatedText, "собака")
    }

    func testCancellationOrFailureResumesMissingTranslation() async {
        let stub = TranslatorStub()
        let draft = makeDraft(translate: stub.translate)
        draft.setSource("kot")
        await waitForRequests(1, in: stub)
        draft.beginDictation()
        draft.endDictation()
        await waitForRequests(2, in: stub)
        stub.requests[0].resume(returning: "старый")
        stub.requests[1].resume(returning: "кот")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(draft.sourceText, "kot")
        XCTAssertEqual(draft.translatedText, "кот")
    }

    func testCancellationPreservesCompletedEditableTranslation() async {
        let stub = TranslatorStub()
        let draft = makeDraft(translate: stub.translate)
        draft.setSource("kot")
        await waitForRequests(1, in: stub)
        stub.requests[0].resume(returning: "кот")
        for _ in 0..<20 { await Task.yield() }
        draft.translatedText = "мой перевод"
        draft.beginDictation()
        draft.endDictation()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(stub.texts, ["kot"])
        XCTAssertEqual(draft.translatedText, "мой перевод")
    }

    func testCancellationPreservesManualTranslationWhileRequestWasPending() async {
        let stub = TranslatorStub()
        let draft = makeDraft(translate: stub.translate)
        draft.setSource("kot")
        await waitForRequests(1, in: stub)
        draft.translatedText = "мой перевод"
        draft.beginDictation()
        draft.endDictation()
        stub.requests[0].resume(returning: "кот")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(stub.texts, ["kot"])
        XCTAssertEqual(draft.translatedText, "мой перевод")
    }

    func testReappearanceResumesCancelledTranslationAndRejectsStaleResponse() async {
        let stub = TranslatorStub()
        let draft = makeDraft(translate: stub.translate)
        draft.setSource("kot")
        await waitForRequests(1, in: stub)
        draft.cancelTranslation()
        draft.resumeTranslationIfNeeded()
        draft.resumeTranslationIfNeeded()
        await waitForRequests(2, in: stub)
        stub.requests[1].resume(returning: "кот")
        for _ in 0..<20 { await Task.yield() }
        stub.requests[0].resume(returning: "старый перевод")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(stub.texts, ["kot", "kot"])
        XCTAssertEqual(draft.translatedText, "кот")
    }

    func testDismissalCancellationRejectsLateFailure() async {
        let stub = TranslatorStub()
        let draft = makeDraft(translate: stub.translate)
        draft.setSource("kot")
        await waitForRequests(1, in: stub)
        draft.cancelTranslation()
        stub.requests[0].resume(throwing: NSError(domain: "dismissed", code: 1))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(draft.translationError)
        XCTAssertFalse(draft.isTranslating)
        XCTAssertTrue(draft.translatedText.isEmpty)
    }

    // MARK: Alternatives

    func testAlternativesDoNotDelayPrimaryAndAppearAfterward() async {
        let stub = TranslatorStub()
        let alts = AlternativesStub()
        let draft = makeDraft(translate: stub.translate, alternatives: alts.fetch)
        draft.setSource("zamek")
        await waitForRequests(1, in: stub)
        await waitForAlternatives(1, in: alts)
        XCTAssertEqual(alts.calls[0].pair, AppLanguage.polish.translationPair)
        stub.requests[0].resume(returning: "замок")
        await settle()
        XCTAssertEqual(draft.translatedText, "замок")
        XCTAssertTrue(draft.translationOptions.isEmpty)
        alts.requests[0].resume(returning: [[alt("замок"), alt("застёжка", "сущ."), alt("zamek")]])
        await settle()
        XCTAssertEqual(draft.translationOptions, [alt("замок"), alt("застёжка", "сущ.")])
    }

    func testSelectingAlternativeUpdatesTranslationWithoutRetranslating() async {
        let stub = TranslatorStub()
        let alts = AlternativesStub()
        let draft = makeDraft(translate: stub.translate, alternatives: alts.fetch)
        draft.setSource("zamek")
        await waitForRequests(1, in: stub)
        await waitForAlternatives(1, in: alts)
        stub.requests[0].resume(returning: "замок")
        alts.requests[0].resume(returning: [[alt("застёжка")]])
        await settle()
        let options = draft.translationOptions
        draft.select(options[1])
        await settle()
        XCTAssertEqual(draft.translatedText, "застёжка")
        XCTAssertFalse(draft.isSelected(options[0]))
        XCTAssertTrue(draft.isSelected(options[1]))
        XCTAssertEqual(stub.texts.count, 1)
        draft.select(options[0])
        XCTAssertEqual(draft.translatedText, "замок")
    }

    func testStaleAlternativesAreIgnoredAfterSourceChange() async {
        let stub = TranslatorStub()
        let alts = AlternativesStub()
        let draft = makeDraft(translate: stub.translate, alternatives: alts.fetch)
        draft.setSource("kot")
        await waitForAlternatives(1, in: alts)
        draft.setSource("pies")
        await waitForAlternatives(2, in: alts)
        await waitForRequests(2, in: stub)
        stub.requests[1].resume(returning: "собака")
        alts.requests[1].resume(returning: [[alt("пёс")]])
        await settle()
        alts.requests[0].resume(returning: [[alt("кошка")]])
        stub.requests[0].resume(returning: "кот")
        await settle()
        XCTAssertEqual(draft.translatedText, "собака")
        XCTAssertEqual(draft.translationOptions, [alt("собака"), alt("пёс")])
    }

    func testPrimaryFailureStillShowsAlternatives() async {
        let stub = TranslatorStub()
        let alts = AlternativesStub()
        let draft = makeDraft(translate: stub.translate, alternatives: alts.fetch)
        draft.setSource("kot")
        await waitForRequests(1, in: stub)
        await waitForAlternatives(1, in: alts)
        stub.requests[0].resume(throwing: NSError(domain: "fail", code: 1))
        alts.requests[0].resume(returning: [[alt("кот"), alt("кошка")]])
        await settle()
        XCTAssertNotNil(draft.translationError)
        XCTAssertTrue(draft.translatedText.isEmpty)
        XCTAssertEqual(draft.translationOptions, [alt("кот"), alt("кошка")])
        draft.select(draft.translationOptions[0])
        XCTAssertEqual(draft.translatedText, "кот")
    }

    func testLongInputSkipsAlternativesFetch() async {
        let stub = TranslatorStub()
        let alts = AlternativesStub()
        let draft = makeDraft(translate: stub.translate, alternatives: alts.fetch)
        draft.setSource("jeden dwa trzy cztery pięć")
        await waitForRequests(1, in: stub)
        stub.requests[0].resume(returning: "один два три четыре пять")
        await settle()
        XCTAssertTrue(alts.calls.isEmpty)
        XCTAssertTrue(draft.translationOptions.isEmpty)
    }

    func testDismissClearsAlternativesAndRejectsLateResponse() async {
        let stub = TranslatorStub()
        let alts = AlternativesStub()
        let draft = makeDraft(translate: stub.translate, alternatives: alts.fetch)
        draft.setSource("kot")
        await waitForRequests(1, in: stub)
        await waitForAlternatives(1, in: alts)
        stub.requests[0].resume(returning: "кот")
        alts.requests[0].resume(returning: [[alt("кошка")]])
        await settle()
        XCTAssertFalse(draft.translationOptions.isEmpty)
        draft.cancelTranslation()
        XCTAssertTrue(draft.translationOptions.isEmpty)

        draft.setSource("pies")
        await waitForRequests(2, in: stub)
        await waitForAlternatives(2, in: alts)
        draft.cancelTranslation()
        alts.requests[1].resume(returning: [[alt("пёс")]])
        stub.requests[1].resume(returning: "собака")
        await settle()
        XCTAssertTrue(draft.translationOptions.isEmpty)
    }

    func testDictationClearsVisibleAlternativesOnlyWhenTextChanges() async {
        let stub = TranslatorStub()
        let alts = AlternativesStub()
        let draft = makeDraft(translate: stub.translate, alternatives: alts.fetch)
        draft.setSource("kot")
        await waitForRequests(1, in: stub)
        await waitForAlternatives(1, in: alts)
        stub.requests[0].resume(returning: "кот")
        alts.requests[0].resume(returning: [[alt("кошка")]])
        await settle()
        let options = draft.translationOptions
        draft.beginDictation()
        XCTAssertEqual(draft.translationOptions, options)
        draft.endDictation()
        await settle()
        XCTAssertEqual(draft.translationOptions, options)
        XCTAssertEqual(stub.texts.count, 1)

        draft.beginDictation()
        draft.commitDictation("pies")
        XCTAssertTrue(draft.translationOptions.isEmpty)
        await waitForAlternatives(2, in: alts)
        XCTAssertEqual(alts.calls[1].text, "pies")
    }

    func testFailedPrimaryWithVisibleChipsSurvivesCancelledDictation() async {
        let stub = TranslatorStub()
        let alts = AlternativesStub()
        let draft = makeDraft(translate: stub.translate, alternatives: alts.fetch)
        draft.setSource("kot")
        await waitForRequests(1, in: stub)
        await waitForAlternatives(1, in: alts)
        stub.requests[0].resume(throwing: NSError(domain: "fail", code: 1))
        alts.requests[0].resume(returning: [[alt("кот")]])
        await settle()
        let options = draft.translationOptions
        XCTAssertFalse(options.isEmpty)
        draft.beginDictation()
        draft.endDictation()
        await settle()
        XCTAssertEqual(stub.texts.count, 1)
        XCTAssertEqual(alts.calls.count, 1)
        XCTAssertEqual(draft.translationOptions, options)
        XCTAssertNotNil(draft.translationError)
    }

    func testPendingAlternativesSurviveCancelledDictation() async {
        let stub = TranslatorStub()
        let alts = AlternativesStub()
        let draft = makeDraft(translate: stub.translate, alternatives: alts.fetch)
        draft.setSource("kot")
        await waitForRequests(1, in: stub)
        await waitForAlternatives(1, in: alts)
        stub.requests[0].resume(returning: "кот")
        await settle()
        draft.beginDictation()
        draft.endDictation()
        alts.requests[0].resume(returning: [[alt("кошка")]])
        await settle()
        XCTAssertEqual(draft.translationOptions, [alt("кот"), alt("кошка")])
        XCTAssertEqual(stub.texts.count, 1)
    }

    func testResumeDuringPendingAlternativesDoesNotRestart() async {
        let stub = TranslatorStub()
        let alts = AlternativesStub()
        let draft = makeDraft(translate: stub.translate, alternatives: alts.fetch)
        draft.setSource("kot")
        await waitForRequests(1, in: stub)
        await waitForAlternatives(1, in: alts)
        stub.requests[0].resume(throwing: NSError(domain: "fail", code: 1))
        await settle()
        draft.resumeTranslationIfNeeded()
        draft.resumeTranslationIfNeeded()
        await settle()
        XCTAssertEqual(stub.texts.count, 1)
        alts.requests[0].resume(returning: [[alt("кот")]])
        await settle()
        XCTAssertEqual(draft.translationOptions, [alt("кот")])
    }
}
