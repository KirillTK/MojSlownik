import XCTest
@testable import MojSlownik

@MainActor
final class ScanResultDraftTests: XCTestCase {
    private final class TranslatorStub {
        var texts: [String] = []
        var requests: [CheckedContinuation<String, Error>] = []

        func translate(_ text: String, source: AppLanguage) async throws -> String {
            texts.append(text)
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
        let draft = ScanResultDraft(sourceText: "kot", debounce: .zero, translate: stub.translate)
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
        let draft = ScanResultDraft(sourceText: "kot", debounce: .zero, translate: stub.translate)
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
}
