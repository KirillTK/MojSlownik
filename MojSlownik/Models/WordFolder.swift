import Foundation
import SwiftData

@Model
final class WordFolder {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date

    init(name: String) {
        self.name = name
        self.createdAt = .now
    }
}
