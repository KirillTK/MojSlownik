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

    private func waitForRequests(_ count: Int, in stub: TranslatorStub) async {
        for _ in 0..<1000 {
            if stub.requests.count >= count { return }
            await Task.yield()
        }
        XCTFail("Translation did not start")
    }

    func testIdenticalDictationRestartsPendingTranslationOnlyOnceAndRejectsStaleError() async {
        let stub = TranslatorStub()
        let draft = AddWordDraft(debounce: .zero, translate: stub.translate)
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
        let draft = AddWordDraft(debounce: .zero, translate: stub.translate)
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
        let draft = AddWordDraft(debounce: .zero, translate: stub.translate)
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
        let draft = AddWordDraft(debounce: .zero, translate: stub.translate)
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
        let draft = AddWordDraft(debounce: .zero, translate: stub.translate)
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
        let draft = AddWordDraft(debounce: .zero, translate: stub.translate)
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
        let draft = AddWordDraft(debounce: .zero, translate: stub.translate)
        draft.setSource("kot")
        await waitForRequests(1, in: stub)
        draft.cancelTranslation()
        stub.requests[0].resume(throwing: NSError(domain: "dismissed", code: 1))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(draft.translationError)
        XCTAssertFalse(draft.isTranslating)
        XCTAssertTrue(draft.translatedText.isEmpty)
    }
}
