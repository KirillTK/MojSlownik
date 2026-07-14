import Foundation

/// Запасной веб-переводчик: https://mymemory.translated.net
/// Без ключа. Email в параметре `de` поднимает лимит с 5 000 до 50 000 символов/день.
/// Качество краудсорсных совпадений нестабильно, поэтому результат валидируется
/// по алфавиту целевого языка, а из `matches` выбирается лучший корректный вариант.
struct MyMemoryTranslator: TranslationService {
    /// Необязательно; можно заменить или убрать.
    var contactEmail: String? = "ktkachyov@gmail.com"

    func translate(_ text: String, from source: AppLanguage, to target: AppLanguage) async throws -> String {
        var components = URLComponents(string: "https://api.mymemory.translated.net/get")!
        var items = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: "\(source.rawValue)|\(target.rawValue)"),
        ]
        if let contactEmail {
            items.append(URLQueryItem(name: "de", value: contactEmail))
        }
        components.queryItems = items

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TranslationError.badResponse
        }

        struct Payload: Decodable {
            struct ResponseData: Decodable {
                let translatedText: String
            }
            struct Match: Decodable {
                let translation: String
                let match: Double?
            }
            let responseData: ResponseData
            let matches: [Match]?
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)

        var candidates = [payload.responseData.translatedText]
        candidates += (payload.matches ?? [])
            .sorted { ($0.match ?? 0) > ($1.match ?? 0) }
            .map(\.translation)

        for candidate in candidates {
            let cleaned = unescape(candidate)
            if isValid(cleaned, sourceText: text, target: target) {
                return cleaned
            }
        }
        throw TranslationError.emptyResult
    }

    /// Отсекает пустые ответы, «перевод = оригинал» и неправильный алфавит.
    private func isValid(_ translated: String, sourceText: String, target: AppLanguage) -> Bool {
        guard !translated.isEmpty,
              translated.lowercased() != sourceText.lowercased() else { return false }
        let hasCyrillic = translated.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
        return target == .russian ? hasCyrillic : !hasCyrillic
    }

    private func unescape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
