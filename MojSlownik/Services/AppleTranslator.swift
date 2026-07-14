import SwiftUI
#if canImport(Translation)
import Translation
#endif

// Офлайн-перевод Apple (Translation framework, iOS 18+).
// Особенность API: TranslationSession выдаётся только через view-модификатор
// .translationTask, поэтому нужен «мост»: модель хранит запрос и continuation,
// модификатор AppleTranslationHost (висит на корневом view) выполняет перевод.

#if canImport(Translation)
@available(iOS 18.0, *)
@MainActor
final class AppleTranslationModel: ObservableObject {
    static let shared = AppleTranslationModel()

    @Published var configuration: TranslationSession.Configuration?
    private var pending: (text: String, continuation: CheckedContinuation<String, Error>)?

    func translate(_ text: String, from source: AppLanguage, to target: AppLanguage) async throws -> String {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending?.continuation.resume(throwing: CancellationError())
                pending = (text, continuation)

                let sourceLanguage = Locale.Language(identifier: source.rawValue)
                let targetLanguage = Locale.Language(identifier: target.rawValue)
                if configuration?.source == sourceLanguage, configuration?.target == targetLanguage {
                    configuration?.invalidate()
                } else {
                    configuration = TranslationSession.Configuration(source: sourceLanguage, target: targetLanguage)
                }
            }
        } onCancel: {
            // Иначе continuation зависает навсегда, если сессия так и не пришла
            // (нет языковых пакетов и т.п.), и таймаут в Translator не срабатывает.
            Task { @MainActor in
                AppleTranslationModel.shared.cancelPending()
            }
        }
    }

    func cancelPending() {
        pending?.continuation.resume(throwing: CancellationError())
        pending = nil
    }

    func run(session: TranslationSession) async {
        guard let job = pending else { return }
        pending = nil
        do {
            let response = try await session.translate(job.text)
            job.continuation.resume(returning: response.targetText)
        } catch {
            job.continuation.resume(throwing: error)
        }
    }
}

@available(iOS 18.0, *)
private struct AppleTranslationHost18: ViewModifier {
    @StateObject private var model = AppleTranslationModel.shared

    func body(content: Content) -> some View {
        content.translationTask(model.configuration) { session in
            await model.run(session: session)
        }
    }
}
#endif

/// Вешается на корневой view; на iOS < 18 ничего не делает.
struct AppleTranslationHost: ViewModifier {
    func body(content: Content) -> some View {
        #if canImport(Translation)
        if #available(iOS 18.0, *) {
            content.modifier(AppleTranslationHost18())
        } else {
            content
        }
        #else
        content
        #endif
    }
}
