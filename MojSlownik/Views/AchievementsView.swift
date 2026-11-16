import SwiftUI
import SwiftData

/// Works both pushed from Training and as the root of its own tab; it owns no NavigationStack.
struct AchievementsView: View {
    @Query private var words: [Word]
    @Query private var folders: [WordFolder]
    @Environment(AchievementStore.self) private var store

    var body: some View {
        let vocabulary = AchievementMetrics.vocabulary(words: words, folderCount: folders.count)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                ForEach(AchievementCategory.allCases, id: \.self) { category in
                    let items = store.catalog.filter { $0.category == category }
                    if !items.isEmpty {
                        section(category, items: items, vocabulary: vocabulary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color.appBackground)
        .foregroundStyle(Color.appInk)
        .navigationTitle("Достижения")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "trophy.fill")
                    .font(.title2)
                    .foregroundStyle(Color.appAccent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(store.totalPoints) очков")
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                    Text("\(store.unlockedCount) из \(store.catalog.count) получено")
                        .font(.subheadline)
                        .foregroundStyle(Color.subtleText)
                }
                Spacer(minLength: 0)
            }
            ProgressView(value: Double(store.unlockedCount), total: Double(max(store.catalog.count, 1)))
                .tint(.appAccent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Label("Серия: \(store.currentStreak()) дн.", systemImage: "flame")
                    .font(.subheadline.weight(.medium))
                Text("Рекорд: \(store.ledger.longestStreakDays) дн.")
                    .font(.subheadline)
                    .foregroundStyle(Color.subtleText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSecondarySurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func section(_ category: AchievementCategory, items: [AchievementDefinition],
                         vocabulary: AchievementMetrics) -> some View {
        let done = items.filter { store.unlocked[$0.id] != nil }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(category.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.subtleText)
                Spacer(minLength: 0)
                Text("\(done)/\(items.count)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Color.subtleText)
            }
            .accessibilityElement(children: .combine)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().overlay(Color.appBorder.opacity(0.5)) }
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
                    Text("Секретное достижение").font(.headline)
                } else {
                    Text(item.title).font(.headline)
                    Text(item.detail)
                        .font(.subheadline)
                        .foregroundStyle(Color.subtleText)
                    status(progress)
                }
            }
            Spacer(minLength: 0)
            Text("\(item.points)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(progress.isUnlocked ? Color.appAccent : Color.subtleText)
        }
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func status(_ progress: AchievementProgress) -> some View {
        if let date = progress.unlockedAt {
            Text("Получено \(date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "ru_RU"))))")
                .font(.caption)
                .foregroundStyle(Color.appAccent)
        } else {
            ProgressView(value: progress.fraction)
                .tint(.appAccent)
                .accessibilityHidden(true)
            Text("\(progress.current) из \(progress.target)")
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
