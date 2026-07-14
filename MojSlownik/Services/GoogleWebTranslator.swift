import Foundation

/// Неофициальный бесплатный эндпоинт Google Translate (client=gtx).
/// Без ключа, качество заметно выше MyMemory. Для личного использования.
struct GoogleWebTranslator: TranslationService {
    func translate(_ text: String, from source: AppLanguage, to target: AppLanguage) async throws -> String {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: source.rawValue),
            URLQueryItem(name: "tl", value: target.rawValue),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text),
        ]

        // «+» не входит в urlQueryAllowed-экранирование, а сервер трактует его как пробел.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")

        let (data, response) = try await URLSession.shared.data(from: components.url!)
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
