import SwiftUI
import SwiftData

struct FlashcardsView: View {
    var folderID: UUID? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(WorkspaceStore.self) private var workspaces
    @Environment(DailyStudyStore.self) private var dailyStudy
    @Environment(AchievementStore.self) private var achievements
    @Query private var storedAllWords: [Word]
    @Query private var storedMemberships: [FolderMembership]
    private var memberships: MembershipIndex { MembershipIndex(storedMemberships) }
    private var allWords: [Word] { WorkspaceScope.words(storedAllWords, workspaceID: workspaces.activeID) }

    @State private var sessionWords: [Word] = []
    @State private var currentIndex = 0
    @State private var isFlipped = false
    @State private var reviewedCount = 0
    @State private var sessionStarted = false
    @State private var reviewError: String?
    @State private var frontSide: WordSide = Bool.random() ? .translation : .term
    @ScaledMetric(relativeTo: .largeTitle) private var cardWordSize: CGFloat = 38
    @ScaledMetric(relativeTo: .largeTitle) private var completedIconSize: CGFloat = 40

    private var currentWord: Word? {
        sessionWords.indices.contains(currentIndex) ? sessionWords[currentIndex] : nil
    }

    var body: some View {
        Group {
            if let word = currentWord {
                sessionView(word: word)
            } else if sessionStarted {
                completedView
            } else {
                emptyView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .foregroundStyle(Color.appInk)
        .tint(Color.appAccentText)
        .navigationTitle("Flashcards")
        .navigationBarTitleDisplayMode(.inline)
        .errorAlert(title: "Couldn’t save the answer", error: $reviewError)
        .onAppear(perform: startSession)
    }

    private func startSession() {
        let words = FolderStore.words(allWords, in: folderID, memberships: memberships)
        guard sessionWords.isEmpty, !words.isEmpty else { return }
        dailyStudy.refresh()
        let due = dailyStudy.reviewWords(for: words).shuffled()
        // Free practice stays available even after today's repetitions are complete.
        sessionWords = due.isEmpty ? Array(words.shuffled().prefix(10)) : due
        sessionStarted = true
    }

    private func sessionView(word: Word) -> some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                SessionProgress(completed: reviewedCount, total: sessionWords.count)
                VStack(spacing: AppSpacing.xl) {
                    card(word: word)

                    if isFlipped {
                        gradeButtons(word: word)
                    } else {
                        Text("Recall the translation, then reveal the answer.")
                            .font(.subheadline)
                            .foregroundStyle(Color.subtleText)
                            .multilineTextAlignment(.center)
                    }
                }
                .id(currentIndex)
                .transition(reduceMotion
                            ? .opacity
                            : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                          removal: .opacity))
            }
            .padding(AppSpacing.l)
        }
        .sensoryFeedback(.selection, trigger: reviewedCount)
    }

    private func card(word: Word) -> some View {
        let shownSide = isFlipped ? frontSide.other : frontSide
        let shownText = word.text(on: shownSide)
        let frontText = word.text(on: frontSide)
        let backText = word.text(on: frontSide.other)
        let tier = KnowledgeProgressService.tier(for: word)
        let cardShape = RoundedRectangle(cornerRadius: AppRadius.flashcard, style: .continuous)

        return Button {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.35)) {
                isFlipped.toggle()
            }
        } label: {
            ZStack {
                frontFace(word: word, side: frontSide, text: frontText, tier: tier)
                    .modifier(FlipFace(angle: isFlipped ? 180 : 0, isVisible: !isFlipped))
                    .accessibilityHidden(isFlipped)
                backFace(word: word, side: frontSide.other, text: backText,
                         original: frontText, tier: tier)
                    .modifier(FlipFace(angle: isFlipped ? 0 : -180, isVisible: isFlipped))
                    .accessibilityHidden(!isFlipped)
            }
            .frame(maxWidth: .infinity, minHeight: 300)
            .background(Color.cardBackground, in: cardShape)
            .overlay { cardShape.strokeBorder(Color.appCardEdge, lineWidth: 1) }
            .contentShape(cardShape)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("flashcard")
        .accessibilityLabel(isFlipped ? "\(frontText) — \(backText)" : frontText)
        .accessibilityValue(KnowledgeTierBadge.accessibilityDescription(
            for: word, level: tier, hidesWord: shownSide == .translation))
        .accessibilityHint(isFlipped ? "Hide translation" : "Show translation")
        .accessibilityAddTraits(.isButton)
        .overlay(alignment: .topTrailing) {
            if shownSide == .term {
                // Sibling of the reveal button, so speaking never flips the card.
                PronounceButton(text: shownText, language: workspaces.pair.term)
                    .padding(AppSpacing.s)
            }
        }
    }

    private func faceHeader(side: WordSide, word: Word, tier: Int) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Text(workspaces.pair.language(of: side).endonym)
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(Color.subtleText)
            KnowledgeTierBadge(word: word, level: tier,
                               hidesWordInAccessibilityLabel: side == .translation)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.trailing, 56)
    }

    private func frontFace(word: Word, side: WordSide, text: String, tier: Int) -> some View {
        VStack(spacing: AppSpacing.m) {
            faceHeader(side: side, word: word, tier: tier)
            Spacer(minLength: 0)
            Text(text)
                .font(.system(size: cardWordSize, weight: .heavy))
                .foregroundStyle(Color.appInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func backFace(word: Word, side: WordSide, text: String,
                          original: String, tier: Int) -> some View {
        VStack(spacing: AppSpacing.m) {
            faceHeader(side: side, word: word, tier: tier)
            Spacer(minLength: 0)
            Text(original)
                .font(.headline)
                .foregroundStyle(Color.subtleText)
                .multilineTextAlignment(.center)
            Rectangle()
                .fill(Color.appBorder)
                .frame(height: 1)
                .containerRelativeFrame(.horizontal) { width, _ in width * 0.5 }
            Text(text)
                .font(.system(size: cardWordSize, weight: .heavy))
                .foregroundStyle(Color.appInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func gradeButtons(word: Word) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text("How easily did you recall it?")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.subtleText)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.s),
                                     count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: AppSpacing.s) {
                ForEach(ReviewGrade.allCases, id: \.self) { grade in
                    Button {
                        apply(grade, to: word)
                    } label: {
                        Text(grade.title)
                            .font(.body.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundStyle(gradeTint(grade))
                            .background(gradeSurface(grade),
                                        in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                            .overlay {
                                if grade != .easy {
                                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                        .strokeBorder(Color.appBorder, lineWidth: 1)
                                }
                            }
                            .contentShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("gradeButton-\(grade.rawValue)")
                }
            }
        }
    }

    private func gradeTint(_ grade: ReviewGrade) -> Color {
        switch grade {
        case .again: .appError
        case .hard, .good: .appInk
        case .easy: .appOnAccent
        }
    }

    private func gradeSurface(_ grade: ReviewGrade) -> Color {
        grade == .easy ? .appAccent : .cardBackground
    }

    private func apply(_ grade: ReviewGrade, to word: Word) {
        do {
            try dailyStudy.review(grade, to: word, context: modelContext)
        } catch {
            reviewError = error.localizedDescription
            return
        }
        achievements.record(.answer(mode: .flashcards, isCorrect: grade != .again))
        if grade == .again {
            sessionWords.append(word)
        }
        reviewedCount += 1
        // Change the word without a flip that could obscure the next prompt.
        isFlipped = false
        if reduceMotion {
            currentIndex += 1
        } else {
            withAnimation(.snappy(duration: 0.3)) { currentIndex += 1 }
        }
        frontSide = Bool.random() ? .translation : .term
    }

    private var completedView: some View {
        ScrollView {
            VStack(spacing: AppSpacing.l) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: completedIconSize))
                    .fontWeight(.medium)
                    .foregroundStyle(Color.appInk)
                    .padding(AppSpacing.m)
                    .background(Color.appAccentSoft, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
                    .accessibilityHidden(true)
                Text("Practice complete")
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("flashcardsCompleted")
                Text("Words reviewed: \(Set(sessionWords.map(\.persistentModelID)).count)")
                    .font(.title3.weight(.medium))
                Label("Total answers: \(reviewedCount)", systemImage: "checklist")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.subtleText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.cardBackground, in: Capsule())
                    .overlay { Capsule().strokeBorder(Color.appCardEdge, lineWidth: 1) }
                Button("Back to Practice") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("backToPracticeButton")
                    .padding(.top, AppSpacing.xs)
            }
            .padding(AppSpacing.xl)
        }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No words", systemImage: "rectangle.on.rectangle.slash")
        } description: {
            Text("Add words to the dictionary first.")
        }
    }
}

/// Rotates one card face around Y; the angle drives visibility so faces swap at the edge-on midpoint.
/// With Reduce Motion the faces crossfade without rotating.
private struct FlipFace: ViewModifier {
    let angle: Double
    let isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(isVisible ? 1 : 0)
        } else {
            content
                .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .modifier(FaceVisibility(angle: angle))
        }
    }
}

private struct FaceVisibility: ViewModifier, Animatable {
    var angle: Double

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity(abs(angle) < 90 ? 1 : 0)
    }
}

#Preview {
    let resources = AppResources.preview
    NavigationStack {
        FlashcardsView()
    }
    .modelContainer(resources.container)
    .environment(resources.workspaces)
    .environment(resources.folders)
    .environment(resources.vocabulary)
    .environment(resources.dailyStudy)
    .environment(resources.achievements)
}
