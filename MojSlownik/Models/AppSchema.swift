import SwiftData

/// The persisted model list: every `ModelContainer` in the app and in tests is built from it.
enum AppSchema {
    static let models: [any PersistentModel.Type] = [Word.self, WordFolder.self, Workspace.self]

    static var schema: Schema { Schema(models) }
}
