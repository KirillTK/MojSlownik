import Foundation

protocol TranslationService {
    func translate(_ text: String, from source: AppLanguage, to target: AppLanguage) async throws -> String
}

enum TranslationError: LocalizedError {
    case emptyResult
    case badResponse
    case timeout

    var errorDescription: String? {
        switch self {
        case .emptyResult: "Перевод не найден"
        case .badResponse: "Сервис перевода недоступен"
        case .timeout: "Перевод занял слишком много времени"
        }
    }
}

/// Единая точка входа: на iOS 18+ пробует офлайн-перевод Apple,
/// затем Google (веб, лучшее качество), затем MyMemory (веб, запасной).
enum Translator {
    static func translate(_ text: String, from source: AppLanguage, to target: AppLanguage) async throws -> String {
        #if DEBUG
        if UITestLaunchConfiguration.current != nil {
            return UITestTranslationStub.translate(text, from: source, to: target)
        }
        #endif
        // В симуляторе Translation framework не работает и показывает
        // системный экран ошибки поверх приложения — путь отключён целиком.
        #if canImport(Translation) && !targetEnvironment(simulator)
        if #available(iOS 18.0, *) {
            do {
                return try await withTimeout(seconds: 4) {
                    try await AppleTranslationModel.shared.translate(text, from: source, to: target)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Языковые пакеты не скачаны, симулятор и т.п. — падаем на веб-API.
            }
        }
        #endif
        return try await webFallback(from: source, to: target,
                                     primary: { try await GoogleWebTranslator().translate(text, from: source, to: target) },
                                     fallback: { try await MyMemoryTranslator().translate(text, from: source, to: target) })
    }

    /// Google, then MyMemory. Logs `translation.failed` only when both fail and the request was
    /// not cancelled; the text itself is never logged (languages and error code only).
    static func webFallback(from source: AppLanguage, to target: AppLanguage,
                            primary: () async throws -> String,
                            fallback: () async throws -> String) async throws -> String {
        do {
            return try await primary()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            do {
                return try await fallback()
            } catch {
                if !Task.isCancelled {
                    await AppLog.record(.translationFailed, error: error,
                                        [.language: .name(source), .targetLanguage: .name(target)])
                }
                throw error
            }
        }
    }

    private static func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw TranslationError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
