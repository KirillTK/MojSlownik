import SwiftUI
import SwiftData

/// Mounted once at the root: keeps unlocks in sync with the dictionary and ledger. Renders nothing.
struct AchievementTracker: View {
    private struct SyncKey: Equatable {
        let vocabulary: AchievementMetrics
        let ledger: AchievementLedger
    }

    @Query private var words: [Word]
    @Query private var folders: [WordFolder]
    @Environment(AchievementStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let vocabulary = AchievementMetrics.vocabulary(words: words, folderCount: folders.count)
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: SyncKey(vocabulary: vocabulary, ledger: store.ledger), initial: true) {
                store.sync(vocabulary: vocabulary)
            }
            .onChange(of: scenePhase, initial: true) {
                store.setSceneActive(scenePhase == .active)
            }
    }
}
