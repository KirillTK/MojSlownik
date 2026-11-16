import Foundation

/// Неофициальный бесплатный эндпоинт Google Translate (client=gtx).
/// Без ключа, качество заметно выше MyMemory. Для личного использования.
struct GoogleWebTranslator: TranslationService {
    static func url(for text: String, pair: TranslationPair, dt: [String], interfaceLanguage: String? = nil) -> URL {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        var items = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: pair.source.googleCode),
            URLQueryItem(name: "tl", value: pair.target.googleCode),
        ]
        if let interfaceLanguage {
            items.append(URLQueryItem(name: "hl", value: interfaceLanguage))
        }
        items += dt.map { URLQueryItem(name: "dt", value: $0) }
        items.append(URLQueryItem(name: "q", value: text))
        components.queryItems = items

        // «+» не входит в urlQueryAllowed-экранирование, а сервер трактует его как пробел.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }

    func translate(_ text: String, from source: AppLanguage, to target: AppLanguage) async throws -> String {
        let pair = TranslationPair(source: source.translationLanguage, target: target.translationLanguage)
        let url = Self.url(for: text, pair: pair, dt: ["t"])

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TranslationError.badResponse
        }

        // Формат ответа: [[["перевод","оригинал",...], ...], ...]
        guard let root = try JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = root.first as? [Any] else {
            throw TranslationError.badResponse
        }

        let translated = segments
            .compactMap { ($0 as? [Any])?.first as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !translated.isEmpty else { throw TranslationError.emptyResult }
        return translated
    }
}
