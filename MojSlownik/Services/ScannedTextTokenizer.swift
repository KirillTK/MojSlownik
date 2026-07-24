import Foundation

/// Делит распознанную строку на слова и промежуточный текст, сохраняя пунктуацию.
enum ScannedTextTokenizer {
    enum Token: Equatable {
        case word(String)
        case text(String)
    }

    private static let wordCharacters = CharacterSet.alphanumerics.union(
        .init(charactersIn: "ąćęłńóśźżĄĆĘŁŃÓŚŹŻ'-")
    )

    static func tokens(in text: String) -> [Token] {
        var tokens: [Token] = []
        var buffer = ""
        var bufferingWord: Bool?

        for character in text {
            let isWordCharacter = character.unicodeScalars.allSatisfy(wordCharacters.contains)
            if bufferingWord != nil && bufferingWord != isWordCharacter {
                append(buffer, isWord: bufferingWord == true, to: &tokens)
                buffer = ""
            }
            bufferingWord = isWordCharacter
            buffer.append(character)
        }
        append(buffer, isWord: bufferingWord == true, to: &tokens)
        return tokens
    }

    static func words(in text: String) -> [String] {
        tokens(in: text).compactMap {
            guard case let .word(word) = $0, word.count > 1 else { return nil }
            return word
        }
    }

    private static func append(_ value: String, isWord: Bool, to tokens: inout [Token]) {
        guard !value.isEmpty else { return }
        tokens.append(isWord ? .word(value) : .text(value))
    }
}
