import Foundation

/// Active memberships indexed both ways; views and stores read folders of a word through it.
struct MembershipIndex {
    private let byWord: [UUID: Set<UUID>]
    private let byFolder: [UUID: Set<UUID>]

    init(_ memberships: [FolderMembership]) {
        var words: [UUID: Set<UUID>] = [:]
        var folders: [UUID: Set<UUID>] = [:]
        for membership in memberships where membership.isActive {
            words[membership.wordID, default: []].insert(membership.folderID)
            folders[membership.folderID, default: []].insert(membership.wordID)
        }
        byWord = words
        byFolder = folders
    }

    func folderIDs(of wordID: UUID) -> Set<UUID> { byWord[wordID] ?? [] }
    func wordIDs(in folderID: UUID) -> Set<UUID> { byFolder[folderID] ?? [] }

    func contains(wordID: UUID?, folderID: UUID) -> Bool {
        wordID.map { byWord[$0]?.contains(folderID) ?? false } ?? false
    }
}
