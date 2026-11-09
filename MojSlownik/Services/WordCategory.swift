import Foundation

enum WordCategory: String, CaseIterable, Identifiable {
    case food = "Еда и напитки"
    case home = "Дом"
    case travel = "Путешествия"
    case nature = "Природа"
    case people = "Люди"
    case work = "Работа и учёба"
    case health = "Здоровье"
    case other = "Другое"

    var id: String { rawValue }

    // Exact dictionary matches keep unrelated words out; unknown forms fall back to Other.
    static func detect(russian: String, polish: String) -> WordCategory {
        let candidates = [russian, polish].map(normalize)
        return vocabulary.first { entry in
            candidates.contains { entry.words.contains($0) }
        }?.category ?? .other
    }

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping.lowercased()
    }

    private static let vocabulary: [(category: WordCategory, words: Set<String>)] = [
        (.food, Set("еда|напиток|хлеб|молоко|вода|кофе|чай|сахар|соль|мясо|рыба|сыр|яйцо|яблоко|суп|масло|рис|картофель|овощи|фрукты|завтрак|обед|ужин|jedzenie|napój|chleb|mleko|woda|kawa|herbata|cukier|sól|mięso|ryba|ser|jajko|jabłko|zupa|masło|ryż|ziemniak|warzywa|owoce|śniadanie|obiad|kolacja".components(separatedBy: "|"))),
        (.home, Set("дом|квартира|комната|кухня|дверь|окно|стол|стул|кровать|ванная|лампа|ключ|шкаф|пол|стена|dom|mieszkanie|pokój|kuchnia|drzwi|okno|stół|krzesło|łóżko|łazienka|lampa|klucz|szafa|podłoga|ściana".components(separatedBy: "|"))),
        (.travel, Set("поезд|автобус|самолёт|самолет|машина|билет|вокзал|аэропорт|улица|дорога|город|отель|паспорт|поездка|путешествие|pociąg|autobus|samolot|samochód|bilet|dworzec|lotnisko|ulica|droga|miasto|hotel|paszport|podróż".components(separatedBy: "|"))),
        (.nature, Set("дерево|цветок|лес|река|море|гора|солнце|дождь|снег|ветер|собака|кошка|кот|птица|земля|небо|drzewo|kwiat|las|rzeka|morze|góra|słońce|deszcz|śnieg|wiatr|pies|kot|ptak|ziemia|niebo".components(separatedBy: "|"))),
        (.people, Set("человек|мужчина|женщина|ребёнок|ребенок|семья|мама|папа|мать|отец|брат|сестра|друг|подруга|człowiek|mężczyzna|kobieta|dziecko|rodzina|mama|tata|matka|ojciec|brat|siostra|przyjaciel|przyjaciółka".components(separatedBy: "|"))),
        (.work, Set("работа|школа|университет|учитель|ученик|студент|книга|тетрадь|ручка|офис|компьютер|урок|экзамен|praca|szkoła|uniwersytet|nauczyciel|uczeń|student|książka|zeszyt|długopis|biuro|komputer|lekcja|egzamin".components(separatedBy: "|"))),
        (.health, Set("врач|больница|аптека|лекарство|здоровье|боль|голова|рука|нога|сердце|зуб|lekarz|szpital|apteka|lek|zdrowie|ból|głowa|ręka|noga|serce|ząb".components(separatedBy: "|")))
    ]
}
