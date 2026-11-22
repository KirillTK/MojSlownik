import CryptoKit
import Foundation

extension UUID {
    /// RFC 4122 name-based UUID, version 5 (SHA-1 over the namespace bytes and the UTF-8 name).
    static func v5(namespace: UUID, name: String) -> UUID {
        var input = withUnsafeBytes(of: namespace.uuid) { Data($0) }
        input.append(contentsOf: Array(name.utf8))
        var bytes = Array(Insecure.SHA1.hash(data: input).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

/// A workspace is identified by its language pair, so devices (and the server) agree on the id.
enum WorkspaceID {
    static let namespace = UUID(uuidString: "A4F06F42-4F0B-43F6-BFB4-33545DCF1307")!

    static func make(term: String, translation: String) -> UUID {
        UUID.v5(namespace: namespace, name: "\(term)>\(translation)")
    }

    /// pl ← ru: where every word and folder created before workspaces lives.
    static let legacy = make(term: "pl", translation: "ru")
}

/// Local identity of a word <-> folder membership (client-only; the server keys by word and folder).
enum MembershipID {
    static let namespace = UUID(uuidString: "4E7EF163-A08F-4BF2-90BD-ABFDF88826C2")!

    static func make(wordID: UUID, folderID: UUID) -> UUID {
        UUID.v5(namespace: namespace, name: "\(wordID.uuidString.lowercased())/\(folderID.uuidString.lowercased())")
    }
}
