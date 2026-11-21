import XCTest
import SwiftData
@testable import MojSlownik

/// Frozen copy of the persisted schema at d593a09 (before uuid/updatedAt/deletedAt).
enum LegacySchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Word.self, WordFolder.self] }

    @Model
    final class Word {
        var russian: String
        var polish: String
        var sourceLanguageCode: String
        var categoryRawValue: String = "Другое"
        var folderIDs: [UUID] = []
        var createdAt: Date
        var easeFactor: Double
        var intervalDays: Double
        var repetitions: Int
        var dueDate: Date
        var lastReviewGradeRawValue: String? = nil
        var knowledgeTier: Int? = nil
        var consecutiveSoftMisses: Int = 0

        init(russian: String, polish: String, createdAt: Date) {
            self.russian = russian
            self.polish = polish
            self.sourceLanguageCode = "pl"
            self.createdAt = createdAt
            self.easeFactor = 2.5
            self.intervalDays = 0
            self.repetitions = 0
            self.dueDate = createdAt
        }
    }

    @Model
    final class WordFolder {
        var id: UUID = UUID()
        var name: String
        var createdAt: Date
        var sortOrder: Int = 0

        init(name: String) {
            self.name = name
            self.createdAt = .now
        }
    }
}

/// Frozen copy of the persisted schema at fc63812 (uuid/updatedAt/deletedAt, before sync's
/// serverUpdatedAt).
enum LegacySchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [Word.self, WordFolder.self] }

    @Model
    final class Word {
        var russian: String
        var polish: String
        var sourceLanguageCode: String
        var categoryRawValue: String = "Другое"
        var folderIDs: [UUID] = []
        var createdAt: Date
        var uuid: UUID? = nil
        var updatedAt: Date? = nil
        var deletedAt: Date? = nil
        var easeFactor: Double
        var intervalDays: Double
        var repetitions: Int
        var dueDate: Date
        var lastReviewGradeRawValue: String? = nil
        var knowledgeTier: Int? = nil
        var consecutiveSoftMisses: Int = 0

        init(russian: String, polish: String, createdAt: Date) {
            self.russian = russian
            self.polish = polish
            self.sourceLanguageCode = "pl"
            self.createdAt = createdAt
            self.uuid = UUID()
            self.updatedAt = createdAt
            self.easeFactor = 2.5
            self.intervalDays = 0
            self.repetitions = 0
            self.dueDate = createdAt
        }
    }

    @Model
    final class WordFolder {
        var id: UUID = UUID()
        var name: String
        var createdAt: Date
        var sortOrder: Int = 0
        var updatedAt: Date? = nil
        var deletedAt: Date? = nil

        init(name: String) {
            self.name = name
            self.createdAt = .now
            self.updatedAt = createdAt
        }
    }
}

/// Frozen copy of the persisted schema at c3b5bf4 (sync's serverUpdatedAt, before workspaces).
enum LegacySchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] { [Word.self, WordFolder.self] }

    @Model
    final class Word {
        var russian: String
        var polish: String
        var sourceLanguageCode: String
        var categoryRawValue: String = "Другое"
        var folderIDs: [UUID] = []
        var createdAt: Date
        var uuid: UUID? = nil
        var updatedAt: Date? = nil
        var deletedAt: Date? = nil
        var serverUpdatedAt: Date? = nil
        var easeFactor: Double
        var intervalDays: Double
        var repetitions: Int
        var dueDate: Date
        var lastReviewGradeRawValue: String? = nil
        var knowledgeTier: Int? = nil
        var consecutiveSoftMisses: Int = 0

        init(russian: String, polish: String, createdAt: Date) {
            self.russian = russian
            self.polish = polish
            self.sourceLanguageCode = "pl"
            self.createdAt = createdAt
            self.uuid = UUID()
            self.updatedAt = createdAt
            self.easeFactor = 2.5
            self.intervalDays = 0
            self.repetitions = 0
            self.dueDate = createdAt
        }
    }

    @Model
    final class WordFolder {
        var id: UUID = UUID()
        var name: String
        var createdAt: Date
        var sortOrder: Int = 0
        var updatedAt: Date? = nil
        var deletedAt: Date? = nil
        var serverUpdatedAt: Date? = nil

        init(name: String) {
            self.name = name
            self.createdAt = .now
            self.updatedAt = createdAt
        }
    }
}

@MainActor
final class LegacySchemaMigrationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    func testLegacyStoreOpensThroughAppResourcesWithoutLosingWords() throws {
        let legacy = Schema(versionedSchema: LegacySchemaV1.self)
        XCTAssertEqual(legacy.entities.map(\.name).sorted(), ["Word", "WordFolder"])
        XCTAssertEqual(Schema([Word.self, WordFolder.self]).entities.map(\.name).sorted(), ["Word", "WordFolder"])

        let url = directory.appendingPathComponent("dictionary.store")
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let folderID = autoreleasepool { () -> UUID in
            do {
                let container = try ModelContainer(for: legacy,
                                                   configurations: ModelConfiguration(schema: legacy, url: url,
                                                                                      cloudKitDatabase: .none))
                let context = ModelContext(container)
                let folder = LegacySchemaV1.WordFolder(name: "Урок 1")
                context.insert(folder)
                for (index, pair) in [("вода", "woda"), ("кофе", "kawa"), ("хлеб", "chleb")].enumerated() {
                    let word = LegacySchemaV1.Word(russian: pair.0, polish: pair.1,
                                                   createdAt: created.addingTimeInterval(Double(index)))
                    word.repetitions = 3 + index
                    word.intervalDays = 10
                    word.easeFactor = 2.7
                    word.categoryRawValue = WordCategory.food.rawValue
                    word.knowledgeTier = 2
                    if index < 2 { word.folderIDs = [folder.id] }
                    context.insert(word)
                }
                try context.save()
                return folder.id
            } catch {
                XCTFail("Legacy seeding failed: \(error)")
                return UUID()
            }
        }

        let resources = try AppResources(
            configuration: ModelConfiguration(url: url, cloudKitDatabase: .none),
            defaults: UserDefaults(suiteName: "LegacySchemaMigrationTests.\(UUID().uuidString)")!)
        let context = ModelContext(resources.container)
        let words = try context.fetch(FetchDescriptor<Word>()).sorted { $0.createdAt < $1.createdAt }

        XCTAssertEqual(words.count, 3)
        XCTAssertEqual(Set(words.compactMap(\.uuid)).count, 3)
        XCTAssertEqual(words.map(\.polish), ["woda", "kawa", "chleb"])
        for (index, word) in words.enumerated() {
            XCTAssertEqual(word.repetitions, 3 + index)
            XCTAssertEqual(word.intervalDays, 10)
            XCTAssertEqual(word.easeFactor, 2.7)
            XCTAssertEqual(word.category, .food)
            XCTAssertEqual(word.knowledgeTier, 2)
            XCTAssertEqual(word.createdAt, created.addingTimeInterval(Double(index)))
            XCTAssertNil(word.updatedAt)
            XCTAssertNil(word.deletedAt)
            XCTAssertTrue(word.isActive)
            XCTAssertEqual(word.lastModifiedAt, word.createdAt)
        }
        XCTAssertEqual(FolderStore.words(words, in: folderID).map(\.polish), ["woda", "kawa"])
        let folders = try FolderStore.folders(in: context)
        XCTAssertEqual(folders.map(\.id), [folderID])
        XCTAssertNil(folders.first?.updatedAt)
        XCTAssertNil(folders.first?.deletedAt)
        try resources.folders.load()
        XCTAssertEqual(resources.folders.options, [.init(id: folderID, name: "Урок 1")])
    }

    /// Sync adds `serverUpdatedAt` to both models: existing installs open with every row intact
    /// and the new property nil, so every row is dirty until the first link.
    func testSchemaV2StoreOpensWithServerUpdatedAtNilAndEveryRowIntact() throws {
        let legacy = Schema(versionedSchema: LegacySchemaV2.self)
        let url = directory.appendingPathComponent("v2.store")
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let deleted = created.addingTimeInterval(500)
        let ids = [UUID(), UUID(), UUID()]
        let folderID = autoreleasepool { () -> UUID in
            do {
                let container = try ModelContainer(for: legacy,
                                                   configurations: ModelConfiguration(schema: legacy, url: url,
                                                                                      cloudKitDatabase: .none))
                let context = ModelContext(container)
                let folder = LegacySchemaV2.WordFolder(name: "Урок 1")
                folder.deletedAt = nil
                context.insert(folder)
                for (index, pair) in [("вода", "woda"), ("кофе", "kawa"), ("хлеб", "chleb")].enumerated() {
                    let word = LegacySchemaV2.Word(russian: pair.0, polish: pair.1,
                                                   createdAt: created.addingTimeInterval(Double(index)))
                    word.uuid = ids[index]
                    word.repetitions = 2 + index
                    word.folderIDs = [folder.id]
                    if index == 2 { word.deletedAt = deleted }
                    context.insert(word)
                }
                try context.save()
                return folder.id
            } catch {
                XCTFail("Legacy seeding failed: \(error)")
                return UUID()
            }
        }

        let resources = try AppResources(
            configuration: ModelConfiguration(url: url, cloudKitDatabase: .none),
            defaults: UserDefaults(suiteName: "LegacySchemaMigrationTests.\(UUID().uuidString)")!)
        let context = ModelContext(resources.container)
        let words = try context.fetch(FetchDescriptor<Word>()).sorted { $0.createdAt < $1.createdAt }

        XCTAssertEqual(words.map(\.polish), ["woda", "kawa", "chleb"])
        XCTAssertEqual(words.compactMap(\.uuid), ids)
        for (index, word) in words.enumerated() {
            XCTAssertNil(word.serverUpdatedAt)
            XCTAssertTrue(word.isSyncDirty)
            XCTAssertEqual(word.repetitions, 2 + index)
            XCTAssertEqual(word.folderIDs, [folderID])
        }
        XCTAssertEqual(words[2].deletedAt, deleted, "tombstones stay")
        let folders = try context.fetch(FetchDescriptor<WordFolder>())
        XCTAssertEqual(folders.map(\.id), [folderID])
        XCTAssertNil(folders.first?.serverUpdatedAt)
        XCTAssertTrue(try XCTUnwrap(folders.first).isSyncDirty)
    }

    /// Workspaces add an entity and `workspaceID` on both models: a store from the app build before
    /// workspaces opens with every row intact and the whole dictionary in the pl ← ru workspace.
    func testSchemaV3StoreMigratesIntoTheLegacyWorkspaceWithoutChangingAnyRow() throws {
        let legacy = Schema(versionedSchema: LegacySchemaV3.self)
        let url = directory.appendingPathComponent("v3.store")
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let synced = created.addingTimeInterval(900)
        let deleted = created.addingTimeInterval(500)
        let ids = [UUID(), UUID(), UUID()]
        let folderIDs = autoreleasepool { () -> [UUID] in
            do {
                let container = try ModelContainer(for: legacy,
                                                   configurations: ModelConfiguration(schema: legacy, url: url,
                                                                                      cloudKitDatabase: .none))
                let context = ModelContext(container)
                let first = LegacySchemaV3.WordFolder(name: "Урок 1")
                let second = LegacySchemaV3.WordFolder(name: "Урок 2")
                second.deletedAt = deleted
                second.updatedAt = deleted
                first.serverUpdatedAt = synced
                first.updatedAt = synced
                context.insert(first)
                context.insert(second)
                for (index, pair) in [("вода", "woda"), ("кофе", "kawa"), ("хлеб", "chleb")].enumerated() {
                    let word = LegacySchemaV3.Word(russian: pair.0, polish: pair.1,
                                                   createdAt: created.addingTimeInterval(Double(index)))
                    word.uuid = ids[index]
                    word.repetitions = 2 + index
                    word.intervalDays = 4
                    word.easeFactor = 2.1
                    word.knowledgeTier = 1
                    if index == 1 { word.folderIDs = [first.id, second.id] }
                    if index == 2 { word.deletedAt = deleted; word.updatedAt = deleted }
                    if index == 0 { word.updatedAt = synced; word.serverUpdatedAt = synced }
                    context.insert(word)
                }
                try context.save()
                return [first.id, second.id]
            } catch {
                XCTFail("Legacy seeding failed: \(error)")
                return []
            }
        }

        let defaults = UserDefaults(suiteName: "LegacySchemaMigrationTests.\(UUID().uuidString)")!
        let resources = try AppResources(configuration: ModelConfiguration(url: url, cloudKitDatabase: .none),
                                         defaults: defaults)
        let context = ModelContext(resources.container)
        let words = try context.fetch(FetchDescriptor<Word>()).sorted { $0.createdAt < $1.createdAt }

        XCTAssertEqual(words.count, 3)
        XCTAssertEqual(words.map(\.polish), ["woda", "kawa", "chleb"])
        XCTAssertEqual(words.map(\.russian), ["вода", "кофе", "хлеб"])
        XCTAssertEqual(words.compactMap(\.uuid), ids)
        XCTAssertEqual(words.map(\.repetitions), [2, 3, 4])
        XCTAssertTrue(words.allSatisfy { $0.intervalDays == 4 && $0.easeFactor == 2.1 && $0.knowledgeTier == 1 })
        XCTAssertEqual(words.map(\.updatedAt), [synced, created.addingTimeInterval(1), deleted])
        XCTAssertEqual(words.map(\.serverUpdatedAt), [synced, nil, nil])
        XCTAssertEqual(words.map(\.deletedAt), [nil, nil, deleted])
        XCTAssertEqual(words[1].folderIDs, [folderIDs[0], folderIDs[1]], "legacy memberships stay as they were")
        XCTAssertTrue(words.allSatisfy { $0.workspaceID == WorkspaceID.legacy })

        let folders = try context.fetch(FetchDescriptor<WordFolder>()).sorted { $0.name < $1.name }
        XCTAssertEqual(folders.map(\.id), folderIDs)
        XCTAssertEqual(folders.map(\.deletedAt), [nil, deleted])
        XCTAssertEqual(folders.map(\.serverUpdatedAt), [synced, nil])
        XCTAssertTrue(folders.allSatisfy { $0.workspaceID == WorkspaceID.legacy })

        let workspaces = try context.fetch(FetchDescriptor<Workspace>())
        XCTAssertEqual(workspaces.count, 1)
        XCTAssertEqual(workspaces.first?.id, WorkspaceID.legacy)
        XCTAssertEqual([workspaces[0].termLanguageCode, workspaces[0].translationLanguageCode], ["pl", "ru"])
        XCTAssertEqual(workspaces[0].createdAt, created, "created from the earliest word")
        XCTAssertTrue(defaults.bool(forKey: WorkspaceBackfill.markerKey))

        try resources.workspaces.load()
        XCTAssertEqual(resources.workspaces.activeID, WorkspaceID.legacy)
        XCTAssertEqual(resources.folders.options.map(\.id), [folderIDs[0]], "the live folder is listed")
    }
}
