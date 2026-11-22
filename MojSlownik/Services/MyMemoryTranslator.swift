import Foundation

/// Fallback web translator: https://mymemory.translated.net
/// No key needed. An email in the `de` parameter raises the limit from 5,000 to 50,000 characters/day.
/// Crowdsourced matches vary in quality, so the result is validated against the target
/// language's alphabet and the best valid variant is picked from `matches`.
struct MyMemoryTranslator: TranslationService {
    /// Optional; can be replaced or removed.
    var contactEmail: String? = "ktkachyov@gmail.com"

    func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        let pair = TranslationPair(source: source, target: target)
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
        // "+" is not escaped by urlQueryAllowed, and the server treats it as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }

    /// Picks the best valid variant; a quota error or a non-200 `responseStatus` gives badResponse.
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
