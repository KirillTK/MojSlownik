import Foundation

/// Russian plural forms: 1 слово, 3 слова, 11 слов, 21 слово.
enum RussianPlural {
    static func form(_ n: Int, one: String, few: String, many: String) -> String {
        let value = abs(n)
        let lastTwo = value % 100
        let last = value % 10
        if (11...14).contains(lastTwo) { return many }
        switch last {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }

    static func format(_ n: Int, one: String, few: String, many: String) -> String {
        "\(n) " + form(n, one: one, few: few, many: many)
    }

    static func words(_ n: Int) -> String { format(n, one: "слово", few: "слова", many: "слов") }
    static func folders(_ n: Int) -> String { format(n, one: "папка", few: "папки", many: "папок") }
}
