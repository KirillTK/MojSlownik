import XCTest
@testable import MojSlownik

@MainActor
final class WorkspaceLabelsTests: XCTestCase {
    private func option(_ term: String, _ translation: String, order: Int = 0) -> WorkspaceStore.Option {
        .init(id: WorkspaceID.make(term: term, translation: translation), termCode: term,
              translationCode: translation, sortOrder: order)
    }

    func testTitleIsFlagAndStudiedLanguage() {
        let pl = option("pl", "ru")
        XCTAssertEqual(WorkspaceLabels.title(of: pl, among: [pl, option("de", "ru", order: 1)]), "🇵🇱 Польский")
    }

    func testTitleAddsTheTranslationFlagWhenTheStudiedLanguageRepeats() {
        let first = option("de", "ru")
        let second = option("de", "en", order: 1)
        XCTAssertEqual(WorkspaceLabels.title(of: first, among: [first, second]), "🇩🇪 Немецкий ← 🇷🇺")
        XCTAssertEqual(WorkspaceLabels.title(of: second, among: [first, second]), "🇩🇪 Немецкий ← 🇬🇧")
    }

    func testMenuLabelAndName() {
        let de = option("de", "ru")
        XCTAssertEqual(WorkspaceLabels.menuLabel(of: de), "🇩🇪 Немецкий ← 🇷🇺")
        XCTAssertEqual(WorkspaceLabels.name(of: de), "Немецкий ← Русский")
    }

    func testAccessibilityNameUsesTheEndonymOnlyWhenItDiffers() {
        XCTAssertEqual(WorkspaceLabels.accessibilityName(of: .polish), "Польский, Polski")
        XCTAssertEqual(WorkspaceLabels.accessibilityName(of: .russian), "Русский")
    }

    func testWordCountsGroupActiveWordsByWorkspace() {
        let de = WorkspaceID.make(term: "de", translation: "ru")
        let legacy = Word(russian: "кот", polish: "kot", side: .translation)
        let german = Word(entry: WordEntry(term: "das Haus", translation: "дом", enteredSide: .translation),
                          pair: LanguagePair(term: .german, translation: .russian), workspaceID: de)
        let deleted = Word(entry: WordEntry(term: "lernen", translation: "учить", enteredSide: .translation),
                           pair: LanguagePair(term: .german, translation: .russian), workspaceID: de)
        deleted.markDeleted(now: .now)
        let counts = WorkspaceScope.wordCounts([legacy, german, deleted])
        XCTAssertEqual(counts[WorkspaceID.legacy], 1, "rows without a workspace belong to pl ← ru")
        XCTAssertEqual(counts[de], 1, "deleted words are not counted")
    }

    func testRussianPluralForms() {
        XCTAssertEqual(RussianPlural.words(0), "0 слов")
        XCTAssertEqual(RussianPlural.words(1), "1 слово")
        XCTAssertEqual(RussianPlural.words(3), "3 слова")
        XCTAssertEqual(RussianPlural.words(11), "11 слов")
        XCTAssertEqual(RussianPlural.words(12), "12 слов")
        XCTAssertEqual(RussianPlural.words(21), "21 слово")
        XCTAssertEqual(RussianPlural.words(248), "248 слов")
        XCTAssertEqual(RussianPlural.folders(1), "1 папка")
        XCTAssertEqual(RussianPlural.folders(4), "4 папки")
        XCTAssertEqual(RussianPlural.folders(5), "5 папок")
    }
}

final class WorkspaceWizardChoicesTests: XCTestCase {
    private let pl = WorkspaceID.make(term: "pl", translation: "ru")

    func testStatusDistinguishesSameExistingRestorableAndAvailable() {
        let choices = WorkspaceWizardChoices(activeIDs: [pl],
                                             deletedIDs: [WorkspaceID.make(term: "de", translation: "ru")])
        XCTAssertEqual(choices.status(term: .polish, translation: .polish), .sameAsStudied)
        XCTAssertEqual(choices.status(term: .polish, translation: .russian), .existing)
        XCTAssertEqual(choices.status(term: .german, translation: .russian), .restorable)
        XCTAssertEqual(choices.status(term: .english, translation: .russian), .available)
    }

    func testRussianIsPreselectedUnlessItIsTheStudiedLanguage() {
        XCTAssertEqual(WorkspaceWizardChoices.defaultTranslation(for: .polish), .russian)
        XCTAssertNil(WorkspaceWizardChoices.defaultTranslation(for: .russian))
    }

    func testChangingTheStudiedLanguageKeepsOrResetsTheTranslation() {
        XCTAssertEqual(WorkspaceWizardChoices.translation(afterStudying: .german, current: .ukrainian), .ukrainian)
        XCTAssertEqual(WorkspaceWizardChoices.translation(afterStudying: .ukrainian, current: .ukrainian), .russian,
                       "the studied language cannot be the translation")
        XCTAssertNil(WorkspaceWizardChoices.translation(afterStudying: .russian, current: .russian))
        XCTAssertEqual(WorkspaceWizardChoices.translation(afterStudying: .polish, current: nil), .russian)
    }

    func testEveryWizardLanguageIsListedOnceInBothSteps() {
        XCTAssertEqual(Set(Language.studyOrder.map(\.code)), Set(Language.all.map(\.code)))
        XCTAssertEqual(Set(Language.translationOrder.map(\.code)), Set(Language.all.map(\.code)))
        XCTAssertEqual(Language.studyOrder.count, Language.all.count)
        XCTAssertEqual(Language.translationOrder.count, Language.all.count)
    }
}
