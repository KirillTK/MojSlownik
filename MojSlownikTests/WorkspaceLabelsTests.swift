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
        XCTAssertEqual(WorkspaceLabels.title(of: pl, among: [pl, option("de", "ru", order: 1)]), "🇵🇱 Polish")
    }

    func testTitleAddsTheTranslationFlagWhenTheStudiedLanguageRepeats() {
        let first = option("de", "ru")
        let second = option("de", "en", order: 1)
        XCTAssertEqual(WorkspaceLabels.title(of: first, among: [first, second]), "🇩🇪 German ← 🇷🇺")
        XCTAssertEqual(WorkspaceLabels.title(of: second, among: [first, second]), "🇩🇪 German ← 🇬🇧")
    }

    func testMenuLabelAndName() {
        let de = option("de", "ru")
        XCTAssertEqual(WorkspaceLabels.menuLabel(of: de), "🇩🇪 German ← 🇷🇺")
        XCTAssertEqual(WorkspaceLabels.name(of: de), "German ← Russian")
    }

    func testAccessibilityNameUsesTheEndonymOnlyWhenItDiffers() {
        XCTAssertEqual(WorkspaceLabels.accessibilityName(of: .polish), "Polish, Polski")
        XCTAssertEqual(WorkspaceLabels.accessibilityName(of: .english), "English")
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
        let choices = WorkspaceWizardChoices()
        XCTAssertEqual(choices.translation(afterStudying: .german, current: .ukrainian), .ukrainian)
        XCTAssertEqual(choices.translation(afterStudying: .english, current: .english), .russian,
                       "the studied language cannot be the translation")
        XCTAssertEqual(choices.translation(afterStudying: .polish, current: nil), .russian)
        XCTAssertEqual(choices.translation(afterStudying: .german, current: .czech), .russian,
                       "a translation not offered for the new studied language is reset")
    }

    func testWizardListsEachSelectableLanguageOnce() {
        XCTAssertEqual(Set(Language.studyOrder).count, Language.studyOrder.count)
        XCTAssertEqual(Set(Language.translationOrder).count, Language.translationOrder.count)
    }

    /// Every selectable studied language gets a preselected, listed, different translation,
    /// whatever was chosen before; a same-language pair is never available.
    func testNoSameLanguagePairFromTheWizardLists() {
        let choices = WorkspaceWizardChoices()
        XCTAssertEqual(choices.studyLanguages, Language.studyOrder)
        for term in Language.studyOrder {
            for current in [nil] + Language.all.map(Optional.some) {
                let preselected = choices.translation(afterStudying: term, current: current)
                XCTAssertNotNil(preselected, term.code)
                XCTAssertNotEqual(preselected, term)
                XCTAssertTrue(preselected.map(choices.translationLanguages(for: term).contains) ?? false, term.code)
            }
        }
        XCTAssertEqual(choices.status(term: .english, translation: .english), .sameAsStudied)
    }

    /// A deleted legacy pair keeps its languages in the wizard so its words can come back.
    func testDeletedLegacyPairStaysRestorable() {
        let frRu = LanguagePair(term: .french, translation: .russian)
        let ruPl = LanguagePair(term: .russian, translation: .polish)
        let choices = WorkspaceWizardChoices(
            deletedIDs: [WorkspaceID.make(term: "fr", translation: "ru"), WorkspaceID.make(term: "ru", translation: "pl")],
            deletedPairs: [frRu, ruPl])
        XCTAssertEqual(choices.studyLanguages, Language.studyOrder + [.french, .russian])
        XCTAssertEqual(choices.translationLanguages(for: .french), Language.translationOrder)
        XCTAssertEqual(choices.translationLanguages(for: .russian), Language.translationOrder + [.polish])
        XCTAssertEqual(choices.translationLanguages(for: .polish), Language.translationOrder)
        XCTAssertEqual(choices.status(term: .french, translation: .russian), .restorable)
        XCTAssertEqual(choices.status(term: .russian, translation: .polish), .restorable)
        XCTAssertNil(choices.translation(afterStudying: .russian, current: .russian), "nothing preselected")
    }
}
