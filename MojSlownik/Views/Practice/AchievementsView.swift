import SwiftUI
import SwiftData

/// Pushed from Practice; owns no NavigationStack.
struct AchievementsView: View {
    @Query private var storedWords: [Word]
    @Query private var storedFolders: [WordFolder]
    private var words: [Word] { storedWords.filter(\.isActive) }
    private var folders: [WordFolder] { storedFolders.filter(\.isActive) }
    @Environment(AchievementStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let vocabulary = AchievementMetrics.vocabulary(words: words, folderCount: folders.count)
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                header
                ForEach(AchievementCategory.allCases, id: \.self) { category in
                    let items = store.catalog.filter { $0.category == category }
                    if !items.isEmpty {
                        section(category, items: items, vocabulary: vocabulary)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.top, AppSpacing.xs)
            .padding(.bottom, AppSpacing.xl)
        }
        .background(Color.appBackground)
        .foregroundStyle(Color.appInk)
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        let shape = RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
        let secondary = Color.appOnInverse.opacity(0.75)
        return VStack(alignment: .leading, spacing: AppSpacing.s) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("\(store.totalPoints) points")
                    .font(.largeTitle.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(Color.appAccent)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .snappy, value: store.totalPoints)
                Text(verbatim: "\(String(localized: "\(store.unlockedCount) of \(store.catalog.count) unlocked")) · \(String(localized: "best streak \(store.ledger.longestStreakDays) days"))")
                    .font(.subheadline)
                    .foregroundStyle(secondary)
            }
            MarkerProgressBar(value: Double(store.unlockedCount) / Double(max(store.catalog.count, 1)),
                              track: Color.appOnInverse.opacity(0.12), fill: .appAccent)
            Label {
                Text("Streak: \(store.currentStreak()) days")
                    .foregroundStyle(Color.appOnInverse)
            } icon: {
                Image(systemName: "flame").foregroundStyle(Color.appAccent)
            }
            .font(.subheadline.weight(.medium))
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appInverseSurface, in: shape)
        .overlay { shape.strokeBorder(Color.appInverseEdge, lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }

    private func section(_ category: AchievementCategory, items: [AchievementDefinition],
                         vocabulary: AchievementMetrics) -> some View {
        let done = items.filter { store.unlocked[$0.id] != nil }.count
        return VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text(category.title)
                    .font(.footnote.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(Color.subtleText)
                Spacer(minLength: 0)
                Text(verbatim: "\(done)/\(items.count)")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Color.subtleText)
            }
            .accessibilityElement(children: .combine)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().overlay(Color.appBorder) }
                    row(item, vocabulary: vocabulary)
                }
            }
            .padding(.horizontal, 14)
            .cardStyle()
        }
    }

    private func row(_ item: AchievementDefinition, vocabulary: AchievementMetrics) -> some View {
        let progress = store.progress(for: item, vocabulary: vocabulary)
        let isHidden = item.isSecret && !progress.isUnlocked
        return HStack(alignment: .top, spacing: 12) {
            AchievementBadge(symbol: isHidden ? "questionmark" : item.symbol, isUnlocked: progress.isUnlocked)
            VStack(alignment: .leading, spacing: 4) {
                if isHidden {
                    Text("Secret achievement").font(.headline)
                } else {
                    Text(item.title).font(.headline)
                    Text(item.detail)
                        .font(.subheadline)
                        .foregroundStyle(Color.subtleText)
                    status(progress)
                }
            }
            Spacer(minLength: 0)
            Text(verbatim: "\(item.points)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(progress.isUnlocked ? Color.appInk : Color.subtleText)
        }
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func status(_ progress: AchievementProgress) -> some View {
        if let date = progress.unlockedAt {
            Text("Unlocked \(date.formatted(.dateTime.day().month(.wide).year().locale(AppLocale.current)))")
                .font(.caption)
                .foregroundStyle(Color.subtleText)
        } else {
            MarkerProgressBar(value: progress.fraction, height: 4)
            Text("\(progress.current) of \(progress.target)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.subtleText)
        }
    }
}

#Preview {
    let resources = AppResources.preview
    NavigationStack { AchievementsView() }
        .modelContainer(resources.container)
        .environment(resources.achievements)
}
