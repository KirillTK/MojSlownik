import Foundation

struct TranslationAlternative: Equatable, Hashable, Sendable {
    let text: String
    let partOfSpeech: String?
}

/// Shared lenient MyMemory payload (used by MyMemoryTranslator and alternatives).
struct MyMemoryPayload: Decodable {
    struct ResponseData: Decodable { let translatedText: String? }
    struct Match: Decodable {
        let segment: String?
        let translation: String
        let match: Double?
    }

    let responseStatus: Int?        // Int or numeric String; missing/garbage -> nil
    let responseData: ResponseData? // error responses may omit it or send null
    let matches: [Match]?

    private enum CodingKeys: String, CodingKey {
        case responseStatus, responseData, matches
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decodeIfPresent(Int.self, forKey: .responseStatus) {
            responseStatus = value
        } else {
            responseStatus = (try? container.decodeIfPresent(String.self, forKey: .responseStatus))
                .flatMap { Int($0) }
        }
        responseData = (try? container.decodeIfPresent(ResponseData.self, forKey: .responseData)) ?? nil
        matches = (try? container.decodeIfPresent([Match].self, forKey: .matches)) ?? nil
    }
}

enum TranslationAlternatives {
    static let maxAlternatives = 6
    static let myMemoryWarningPrefix = "MYMEMORY WARNING"

    /// Gate: single words and short phrases only.
    static func shouldFetch(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("\n"), !trimmed.contains("\r"),
              trimmed.count <= 60 else { return false }
        return trimmed.split(whereSeparator: \.isWhitespace).count <= 4
    }

    /// Case-folded, trimmed, inner whitespace collapsed.
    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    static func unescape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Descriptor-driven sanity check of a candidate translation.
    static func isValid(_ candidate: String, sourceText: String, pair: TranslationPair) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, normalized(trimmed) != normalized(sourceText) else { return false }

        let sourceOnly = pair.source.scripts.subtracting(pair.target.scripts)
        let allowed = pair.source.scripts.union(pair.target.scripts)
        var hasTargetLetter = false
        var hasLetter = false
        for scalar in trimmed.unicodeScalars where scalar.properties.isAlphabetic {
            hasLetter = true
            guard let script = Script.of(scalar), allowed.contains(script) else { return false }
            if sourceOnly.contains(script) { return false }
            if pair.target.scripts.contains(script) { hasTargetLetter = true }
        }
        return hasTargetLetter || !hasLetter
    }

    /// Google gtx response: `t` segments, then `bd` dictionary terms, then `at` alternatives.
    static func parseGoogle(_ data: Data) -> [TranslationAlternative] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
        var result: [TranslationAlternative] = []

        let segments = root.first as? [Any]
        if let segments {
            let joined = segments
                .compactMap { ($0 as? [Any])?.first as? String }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { result.append(TranslationAlternative(text: joined, partOfSpeech: nil)) }
        }

        if root.count > 1, let entries = root[1] as? [Any] {
            for entry in entries {
                guard let parts = entry as? [Any], let terms = parts.count > 1 ? parts[1] as? [Any] : nil else { continue }
                let pos = (parts.first as? String).flatMap { $0.isEmpty ? nil : $0 }
                for case let term as String in terms {
                    result.append(TranslationAlternative(text: term, partOfSpeech: pos))
                }
            }
        }

        if root.count > 5, let at = root[5] as? [Any], at.count == 1,
           let segment = at[0] as? [Any], segment.count > 2,
           let alts = segment[2] as? [Any] {
            for alt in alts {
                if let text = (alt as? [Any])?.first as? String {
                    result.append(TranslationAlternative(text: text, partOfSpeech: nil))
                }
            }
        }
        return result
    }

    static func parseMyMemory(_ data: Data, sourceText: String) -> [TranslationAlternative] {
        guard let payload = try? JSONDecoder().decode(MyMemoryPayload.self, from: data),
              payload.responseStatus == 200 else { return [] }
        var result: [TranslationAlternative] = []

        if let main = payload.responseData?.translatedText.map(unescape),
           !main.uppercased().hasPrefix(myMemoryWarningPrefix) {
            result.append(TranslationAlternative(text: main, partOfSpeech: nil))
        }

        let key = normalized(sourceText)
        let exact = (payload.matches ?? [])
            .filter { $0.segment.map(normalized) == key }
            .sorted { ($0.match ?? 0) > ($1.match ?? 0) }
        for match in exact {
            let text = unescape(match.translation)
            if text.uppercased().hasPrefix(myMemoryWarningPrefix) { continue }
            result.append(TranslationAlternative(text: text, partOfSpeech: nil))
        }
        return result
    }

    static func merge(primary: String?, groups: [[TranslationAlternative]],
                      sourceText: String, pair: TranslationPair) -> [TranslationAlternative] {
        var all: [TranslationAlternative] = []
        if let primary { all.append(TranslationAlternative(text: primary, partOfSpeech: nil)) }
        all += groups.flatMap { $0 }

        var kept: [TranslationAlternative] = []
        var indexByKey: [String: Int] = [:]
        for item in all {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValid(text, sourceText: sourceText, pair: pair) else { continue }
            let key = normalized(text)
            if let index = indexByKey[key] {
                if kept[index].partOfSpeech == nil, let pos = item.partOfSpeech {
                    kept[index] = TranslationAlternative(text: kept[index].text, partOfSpeech: pos)
                }
            } else {
                indexByKey[key] = kept.count
                kept.append(TranslationAlternative(text: text, partOfSpeech: item.partOfSpeech))
            }
        }

        if let primary {
            let primaryKey = normalized(primary)
            kept.removeAll { normalized($0.text) == primaryKey }
        }
        return Array(kept.prefix(maxAlternatives))
    }
}

enum TranslationAlternativesService {
    /// Google `hl`: language of part-of-speech labels. App UI copy is Russian.
    static let interfaceLanguage = "ru"

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        return URLSession(configuration: configuration)
    }()

    /// Returns [googleCandidates, myMemoryCandidates]; never throws, [] per failed source.
    static func fetch(_ text: String, pair: TranslationPair) async -> [[TranslationAlternative]] {
        #if DEBUG
        if UITestLaunchConfiguration.current != nil {
            return UITestTranslationStub.alternatives(text, pair: pair)
        }
        #endif
        async let google = load(
            GoogleWebTranslator.url(for: text, pair: pair, dt: ["t", "bd", "at"], interfaceLanguage: interfaceLanguage)
        ) { TranslationAlternatives.parseGoogle($0) }
        async let myMemory = load(
            MyMemoryTranslator.url(for: text, pair: pair, contactEmail: MyMemoryTranslator().contactEmail)
        ) { TranslationAlternatives.parseMyMemory($0, sourceText: text) }
        return await [google, myMemory]
    }

    private static func load(_ url: URL, parse: (Data) -> [TranslationAlternative]) async -> [TranslationAlternative] {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            return parse(data)
        } catch {
            return []
        }
    }
}
