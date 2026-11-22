import SwiftUI
import SwiftData

struct TrainingView: View {
    @Environment(WorkspaceStore.self) private var workspaces
    @Environment(DailyStudyStore.self) private var dailyStudy
    @Environment(AchievementStore.self) private var achievements
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var storedAllWords: [Word]
    @Query private var storedMemberships: [FolderMembership]
    private var memberships: MembershipIndex { MembershipIndex(storedMemberships) }
    private var allWords: [Word] { WorkspaceScope.words(storedAllWords, workspaceID: workspaces.activeID) }
    @State private var selectedFolderID: UUID?
    @State private var refreshDate = Date.now
    @ScaledMetric(relativeTo: .largeTitle) private var heroNumber: CGFloat = 40
    @ScaledMetric(relativeTo: .body) private var modeTile: CGFloat = 36
    @ScaledMetric(relativeTo: .body) private var achievementTile: CGFloat = 40

    private var words: [Word] { FolderStore.words(allWords, in: selectedFolderID, memberships: memberships) }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                let now = max(timeline.date, refreshDate)
                let progress = dailyStudy.progress(for: words, now: now)
                let answers = dailyStudy.answerTotals(for: words, now: now)
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.l) {
                        FolderPicker(selectedFolderID: $selectedFolderID, allowsAll: true, compact: true)
                        todayHero(progress: progress, answers: answers)
                        modeGrid
                        achievementsRow(now: now)
                        Text("Words in the selected set: \(words.count)")
                            .font(.footnote)
                            .foregroundStyle(Color.subtleText)
                    }
                    .padding(.horizontal, AppSpacing.l)
                    .padding(.top, AppSpacing.xs)
                    .padding(.bottom, AppSpacing.xl)
                }
            }
            .background(Color.appBackground)
            .foregroundStyle(Color.appInk)
            .workspaceTitleMenu(words: storedAllWords)
            .onChange(of: workspaces.activeID) { selectedFolderID = nil }
            .onAppear { refreshClock() }
            .onChange(of: scenePhase) {
                if scenePhase == .active { refreshClock() }
            }
        }
        .tint(.appAccentText)
    }

    private func refreshClock() {
        refreshDate = .now
        dailyStudy.refresh(now: refreshDate)
    }

    // MARK: Today hero

    private func sectionHeader(_ title: LocalizedStringKey, color: Color = .subtleText) -> some View {
        Text(title)
            .font(.footnote.weight(.bold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(color)
    }

    private func todayHero(progress: DailyStudyStore.Summary, answers: DailyStudyStore.AnswerTotals) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: AppSpacing.s))
        let secondary = Color.appOnAccent.opacity(0.75)
        return VStack(alignment: .leading, spacing: AppSpacing.s) {
            layout {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    sectionHeader("Today", color: secondary)
                    heroLine(progress: progress)
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text(words.isEmpty ? "Start with the dictionary"
                     : progress.remaining > 0 ? "Words left: \(progress.remaining)"
                     : progress.completed > 0 ? "All reviewed" : "Free practice is available")
                    .font(.subheadline)
                    .foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            MarkerProgressBar(value: progress.fraction, track: Color.appOnAccent.opacity(0.12), fill: .appOnAccent)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Reviewed today")
                .accessibilityValue("\(progress.completed) of \(progress.total). Remaining: \(progress.remaining)")
                .accessibilityIdentifier("todayProgress")
            practiceButton(progress: progress)
            layout {
                answerBadge("Correct: \(answers.correct)", icon: "checkmark")
                answerBadge("Incorrect: \(answers.incorrect)", icon: "xmark")
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            }
            Text("Answers: \(answers.total)")
                .font(.caption)
                .foregroundStyle(secondary)
                .accessibilityIdentifier("answerTotal")
        }
        .foregroundStyle(Color.appOnAccent)
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appAccent, in: RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous))
        .animation(reduceMotion ? nil : .snappy, value: progress.completed)
    }

    private func heroLine(progress: DailyStudyStore.Summary) -> some View {
        Group {
            if words.isEmpty {
                Text("Add your first word")
                    .font(.title2.weight(.bold))
            } else if progress.total > 0 {
                Text("\(progress.completed)")
                    .font(.system(size: heroNumber, weight: .heavy))
                    .monospacedDigit()
                + Text(" of \(progress.total)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.appOnAccent.opacity(0.75))
            } else {
                Text("No reviews")
                    .font(.title2.weight(.bold))
            }
        }
        .monospacedDigit()
        .contentTransition(.numericText())
        .fixedSize(horizontal: false, vertical: true)
    }

    private func answerBadge(_ label: LocalizedStringKey, icon: String) -> some View {
        Label(label, systemImage: icon)
            .font(.subheadline.weight(.medium))
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(Color.appOnAccent)
            .padding(.horizontal, AppSpacing.s)
            .padding(.vertical, AppSpacing.xs)
            .background(Color.appOnAccent.opacity(0.12), in: Capsule())
    }

    private func practiceButton(progress: DailyStudyStore.Summary) -> some View {
        NavigationLink {
            FlashcardsView(folderID: selectedFolderID)
        } label: {
            Text(progress.remaining > 0
                 ? progress.completed == 0 ? "Start review · \(progress.remaining)" : "Continue · \(progress.remaining)"
                 : "Free practice")
        }
        .buttonStyle(PrimaryButtonStyle(kind: .inverse))
        .disabled(words.isEmpty)
        .accessibilityHint(progress.remaining > 0 ? "Open flashcards for review" : "Practice up to ten random words")
        .accessibilityIdentifier("practiceStartButton")
    }

    // MARK: Modes

    private var modeGrid: some View {
        let isAX = dynamicTypeSize.isAccessibilitySize
        let columns = isAX
            ? [GridItem(.flexible(), spacing: AppSpacing.s)]
            : [GridItem(.flexible(), spacing: AppSpacing.s), GridItem(.flexible(), spacing: AppSpacing.s)]
        return VStack(alignment: .leading, spacing: AppSpacing.xs) {
            sectionHeader("Modes")
            LazyVGrid(columns: columns, spacing: AppSpacing.s) {
                NavigationLink {
                    FlashcardsView(folderID: selectedFolderID)
                } label: {
                    ModeTile(title: "Flashcards", subtitle: "Recall the translation", icon: "rectangle.on.rectangle",
                             iconSize: modeTile, isWide: isAX)
                }
                .disabled(words.isEmpty)
                .accessibilityIdentifier("flashcardsModeTile")
                NavigationLink {
                    QuizView(folderID: selectedFolderID)
                } label: {
                    ModeTile(title: "Quiz", subtitle: words.count >= 4 ? "Choose the correct answer" : "At least 4 words needed",
                             icon: "checklist", iconSize: modeTile, isWide: isAX)
                }
                .disabled(words.count < 4)
                .accessibilityIdentifier("quizModeTile")
            }
            .buttonStyle(TileButtonStyle())
            NavigationLink {
                ListeningPracticeView(folderID: selectedFolderID)
            } label: {
                ModeTile(title: "Listening", subtitle: "Listen and write \(workspaces.pair.term.names.adverb)", icon: "ear",
                         iconSize: modeTile, isWide: true)
            }
            .buttonStyle(TileButtonStyle())
            .disabled(words.isEmpty)
        }
    }

    // MARK: Achievements row

    private func achievementsRow(now: Date) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: AppSpacing.s))
        return NavigationLink {
            AchievementsView()
        } label: {
            layout {
                Image(systemName: "trophy")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.appInk)
                    .frame(width: achievementTile, height: achievementTile)
                    .background(Color.appAccentSoft, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("Achievements").font(.headline).foregroundStyle(Color.appInk)
                    Text(verbatim: "\(String(localized: "\(achievements.totalPoints) points")) · \(String(localized: "Streak: \(achievements.currentStreak(now: now)) days"))")
                        .font(.subheadline)
                        .foregroundStyle(Color.subtleText)
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                HStack(spacing: AppSpacing.xs) {
                    Text("\(achievements.unlockedCount) of \(achievements.catalog.count)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Color.subtleText)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.subtleText)
                        .accessibilityHidden(true)
                }
            }
            .padding(AppSpacing.s)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .cardStyle()
            .contentShape(Rectangle())
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityElement(children: .combine)
    }
}

/// Renders the label unchanged so the system does not dim the whole tile when disabled.
private struct TileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

private struct ModeTile: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let icon: String
    let iconSize: CGFloat
    let isWide: Bool
    @Environment(\.isEnabled) private var isEnabled

    private var iconTile: some View {
        Image(systemName: icon)
            .font(.body)
            .fontWeight(.medium)
            .foregroundStyle(Color.appInk)
            .frame(width: iconSize, height: iconSize)
            .background(Color.appAccentSoft, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .accessibilityHidden(true)
    }

    private var titleText: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Color.appInk)
            .opacity(isEnabled ? 1 : 0.45)
    }

    private var subtitleText: some View {
        Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(Color.subtleText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        Group {
            if isWide {
                HStack(spacing: AppSpacing.s) {
                    iconTile
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        titleText
                        subtitleText
                    }
                    Spacer(minLength: 0)
                }
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    iconTile
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        titleText
                        subtitleText
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: isWide ? 64 : 96, alignment: .leading)
        .cardStyle()
        .contentShape(Rectangle())
    }
}

#Preview {
    let resources = AppResources.preview
    TrainingView()
        .modelContainer(resources.container)
        .environment(resources.workspaces)
        .environment(resources.folders)
        .environment(resources.vocabulary)
        .environment(resources.dailyStudy)
        .environment(resources.achievements)
}
