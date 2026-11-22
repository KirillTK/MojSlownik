import Foundation

protocol TranslationService {
    func translate(_ text: String, from source: Language, to target: Language) async throws -> String
}

enum TranslationError: LocalizedError {
    case emptyResult
    case badResponse
    case timeout

    var errorDescription: String? {
        switch self {
        case .emptyResult: String(localized: "No translation found")
        case .badResponse: String(localized: "The translation service is unavailable")
        case .timeout: String(localized: "The translation took too long")
        }
    }
}

/// Single entry point: on iOS 18+ tries Apple's offline translation first,
/// then Google (web, best quality), then MyMemory (web, fallback).
enum Translator {
    static func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        #if DEBUG
        if UITestLaunchConfiguration.current != nil {
            return UITestTranslationStub.translate(text, from: source, to: target)
        }
        #endif
        // The Translation framework does not work in the simulator and shows
        // a system error screen over the app, so this path is disabled entirely.
        #if canImport(Translation) && !targetEnvironment(simulator)
        if #available(iOS 18.0, *), source.appleIdentifier != nil, target.appleIdentifier != nil {
            do {
                return try await withTimeout(seconds: 4) {
                    try await AppleTranslationModel.shared.translate(text, from: source, to: target)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Language packs not downloaded, simulator, etc.: fall back to the web APIs.
            }
        }
        #endif
        return try await webFallback(from: source, to: target,
                                     primary: { try await GoogleWebTranslator().translate(text, from: source, to: target) },
                                     fallback: { try await MyMemoryTranslator().translate(text, from: source, to: target) })
    }

    /// Google, then MyMemory. Logs `translation.failed` only when both fail and the request was
    /// not cancelled; the text itself is never logged (languages and error code only).
    static func webFallback(from source: Language, to target: Language,
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
                                        [.language: .name(source.code), .targetLanguage: .name(target.code)])
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
