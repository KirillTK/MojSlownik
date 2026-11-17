import SwiftUI
import SwiftData

struct FlashcardsView: View {
    var folderID: UUID? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(DailyStudyStore.self) private var dailyStudy
    @Environment(AchievementStore.self) private var achievements
    @Query private var allWords: [Word]

    @State private var sessionWords: [Word] = []
    @State private var currentIndex = 0
    @State private var isFlipped = false
    @State private var reviewedCount = 0
    @State private var sessionStarted = false
    @State private var reviewError: String?
    @State private var frontIsRussian = Bool.random()
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
        .navigationTitle("Карточки")
        .navigationBarTitleDisplayMode(.inline)
        .errorAlert(title: "Не удалось сохранить ответ", error: $reviewError)
        .onAppear(perform: startSession)
    }

    private func startSession() {
        let words = FolderStore.words(allWords, in: folderID)
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
                        Text("Вспомните перевод, затем откройте ответ.")
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
        let frontLanguage: AppLanguage = frontIsRussian ? .russian : .polish
        let shownLanguage = isFlipped ? frontLanguage.other : frontLanguage
        let shownText = word.text(in: shownLanguage)
        let frontText = word.text(in: frontLanguage)
        let backText = word.text(in: frontLanguage.other)
        let tier = KnowledgeProgressService.tier(for: word)
        let cardShape = RoundedRectangle(cornerRadius: AppRadius.flashcard, style: .continuous)

        return Button {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.35)) {
                isFlipped.toggle()
            }
        } label: {
            ZStack {
                frontFace(word: word, language: frontLanguage, text: frontText, tier: tier)
                    .modifier(FlipFace(angle: isFlipped ? 180 : 0, isVisible: !isFlipped))
                    .accessibilityHidden(isFlipped)
                backFace(word: word, language: frontLanguage.other, text: backText,
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
            for: word, level: tier, hidesWord: shownLanguage == .russian))
        .accessibilityHint(isFlipped ? "Скрыть перевод" : "Показать перевод")
        .accessibilityAddTraits(.isButton)
        .overlay(alignment: .topTrailing) {
            if shownLanguage == .polish {
                // Sibling of the reveal button, so speaking never flips the card.
                PronounceButton(text: shownText, language: .polish)
                    .padding(AppSpacing.s)
            }
        }
    }

    private func faceHeader(language: AppLanguage, word: Word, tier: Int) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Text(language.displayName)
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(Color.subtleText)
            KnowledgeTierBadge(word: word, level: tier,
                               hidesWordInAccessibilityLabel: language == .russian)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.trailing, 56)
    }

    private func frontFace(word: Word, language: AppLanguage, text: String, tier: Int) -> some View {
        VStack(spacing: AppSpacing.m) {
            faceHeader(language: language, word: word, tier: tier)
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

    private func backFace(word: Word, language: AppLanguage, text: String,
                          original: String, tier: Int) -> some View {
        VStack(spacing: AppSpacing.m) {
            faceHeader(language: language, word: word, tier: tier)
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
            Text("Насколько легко вспомнили?")
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
        frontIsRussian = Bool.random()
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
                Text("Тренировка завершена")
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Повторено слов: \(Set(sessionWords.map(\.persistentModelID)).count)")
                    .font(.title3.weight(.medium))
                Label("Всего ответов: \(reviewedCount)", systemImage: "checklist")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.subtleText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.cardBackground, in: Capsule())
                    .overlay { Capsule().strokeBorder(Color.appCardEdge, lineWidth: 1) }
                Button("К практике") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, AppSpacing.xs)
            }
            .padding(AppSpacing.xl)
        }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("Нет слов", systemImage: "rectangle.on.rectangle.slash")
        } description: {
            Text("Сначала добавьте слова в словарь.")
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
    .environment(FolderLibraryStore())
    .environment(resources.dailyStudy)
    .environment(resources.achievements)
}
