import Foundation

/// Запасной веб-переводчик: https://mymemory.translated.net
/// Без ключа. Email в параметре `de` поднимает лимит с 5 000 до 50 000 символов/день.
/// Качество краудсорсных совпадений нестабильно, поэтому результат валидируется
/// по алфавиту целевого языка, а из `matches` выбирается лучший корректный вариант.
struct MyMemoryTranslator: TranslationService {
    /// Необязательно; можно заменить или убрать.
    var contactEmail: String? = "ktkachyov@gmail.com"

    func translate(_ text: String, from source: AppLanguage, to target: AppLanguage) async throws -> String {
        let pair = TranslationPair(source: source.translationLanguage, target: target.translationLanguage)
        let url = Self.url(for: text, pair: pair, contactEmail: contactEmail)

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TranslationError.badResponse
        }

        return try Self.bestTranslation(from: data, sourceText: text, pair: pair)
    }

    static func url(for text: String, pair: TranslationPair, contactEmail: String?) -> URL {
        var components = URLComponents(string: "https://api.mymemory.translated.net/get")!
        var items = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: "\(pair.source.myMemoryCode)|\(pair.target.myMemoryCode)"),
        ]
        if let contactEmail {
            items.append(URLQueryItem(name: "de", value: contactEmail))
        }
        components.queryItems = items
        // «+» не входит в urlQueryAllowed-экранирование, а сервер трактует его как пробел.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }

    /// Выбирает лучший корректный вариант; квота и не-200 `responseStatus` дают badResponse.
    static func bestTranslation(from data: Data, sourceText: String, pair: TranslationPair) throws -> String {
        let payload: MyMemoryPayload
        do {
            payload = try JSONDecoder().decode(MyMemoryPayload.self, from: data)
        } catch {
            throw TranslationError.badResponse
        }
        guard payload.responseStatus == 200 else { throw TranslationError.badResponse }

        var candidates: [String] = []
        if let main = payload.responseData?.translatedText { candidates.append(main) }
        candidates += (payload.matches ?? [])
            .sorted { ($0.match ?? 0) > ($1.match ?? 0) }
            .map(\.translation)

        for candidate in candidates {
            let cleaned = TranslationAlternatives.unescape(candidate)
            if cleaned.uppercased().hasPrefix(TranslationAlternatives.myMemoryWarningPrefix) { continue }
            if TranslationAlternatives.isValid(cleaned, sourceText: sourceText, pair: pair) {
                return cleaned
            }
        }
        throw TranslationError.emptyResult
    }
}
