import Foundation

/// Бесплатный веб-API перевода: https://mymemory.translated.net
/// Без ключа. Email в параметре `de` поднимает лимит до 50 000 символов/день.
struct MyMemoryTranslator: TranslationService {
    /// Необязательно; можно заменить или убрать.
    var contactEmail: String?

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
            let responseData: ResponseData
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let translated = payload.responseData.translatedText
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !translated.isEmpty else { throw TranslationError.emptyResult }
        return translated
    }
}
