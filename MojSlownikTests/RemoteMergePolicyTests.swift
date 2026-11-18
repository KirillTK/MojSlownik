import XCTest
@testable import MojSlownik

final class RemoteMergePolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var t1: Date { t0.addingTimeInterval(60) }

    private func decide(local: LocalRecordState?, updatedAt: Date, deletedAt: Date? = nil) -> RemoteMergeDecision {
        RemoteMergePolicy.decide(local: local, remoteUpdatedAt: updatedAt, remoteDeletedAt: deletedAt)
    }

    func testNewActiveRemoteRowIsInserted() {
        XCTAssertEqual(decide(local: nil, updatedAt: t1), .insert)
    }

    func testNewRemoteTombstoneIsNotMaterialized() {
        XCTAssertEqual(decide(local: nil, updatedAt: t1, deletedAt: t1), .keepLocal)
    }

    func testNewerRemoteRowUpdatesLocal() {
        XCTAssertEqual(decide(local: LocalRecordState(lastModifiedAt: t0, isDeleted: false), updatedAt: t1), .update)
    }

    func testOlderOrEqualRemoteRowKeepsLocal() {
        let local = LocalRecordState(lastModifiedAt: t1, isDeleted: false)
        XCTAssertEqual(decide(local: local, updatedAt: t0), .keepLocal)
        XCTAssertEqual(decide(local: local, updatedAt: t1), .keepLocal, "ties keep the local row")
        XCTAssertEqual(decide(local: local, updatedAt: t0, deletedAt: t0), .keepLocal)
    }

    func testRemoteDeleteOnlySoftDeletes() {
        let local = LocalRecordState(lastModifiedAt: t0, isDeleted: false)
        XCTAssertEqual(decide(local: local, updatedAt: t1, deletedAt: t1), .softDelete(at: t1))
    }

    func testRemoteDeleteOfAlreadyDeletedRowKeepsLocal() {
        let local = LocalRecordState(lastModifiedAt: t0, isDeleted: true)
        XCTAssertEqual(decide(local: local, updatedAt: t1, deletedAt: t1), .keepLocal)
    }

    func testNewerActiveRemoteRowRestoresLocalTombstone() {
        let local = LocalRecordState(lastModifiedAt: t0, isDeleted: true)
        XCTAssertEqual(decide(local: local, updatedAt: t1), .update)
    }

    /// The decision type has no hard-delete case; this switch stops compiling if one is added.
    func testNoDecisionHardDeletes() {
        let all: [RemoteMergeDecision] = [.insert, .update, .softDelete(at: t0), .keepLocal]
        for decision in all {
            switch decision {
            case .insert, .update, .softDelete, .keepLocal: break
            }
        }
    }

    func testLocalStateComesFromWordAndFolder() {
        let word = Word(russian: "кот", polish: "kot", sourceLanguage: .russian, createdAt: t0)
        XCTAssertEqual(word.localRecordState, LocalRecordState(lastModifiedAt: t0, isDeleted: false))
        word.markDeleted(now: t1)
        XCTAssertEqual(word.localRecordState, LocalRecordState(lastModifiedAt: t1, isDeleted: true))

        let folder = WordFolder(name: "Еда")
        folder.markDeleted(now: t1)
        XCTAssertEqual(folder.localRecordState, LocalRecordState(lastModifiedAt: t1, isDeleted: true))
    }
}
