import SwiftUI
import SwiftData

struct FlashcardsView: View {
    var folderID: UUID? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(DailyStudyStore.self) private var dailyStudy
    @Query private var allWords: [Word]

    @State private var sessionWords: [Word] = []
    @State private var currentIndex = 0
    @State private var isFlipped = false
    @State private var reviewedCount = 0
    @State private var sessionStarted = false
    @State private var reviewError: String?
    @State private var frontIsRussian = Bool.random()

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
        .tint(Color.appAccent)
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
            VStack(spacing: 24) {
                SessionProgress(completed: reviewedCount, total: sessionWords.count)
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
            .padding(20)
        }
    }

    private func card(word: Word) -> some View {
        let frontLanguage: AppLanguage = frontIsRussian ? .russian : .polish
        let shownLanguage = isFlipped ? frontLanguage.other : frontLanguage
        let shownText = word.text(in: shownLanguage)

        return VStack(spacing: 12) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    isFlipped.toggle()
                }
            } label: {
                VStack(spacing: 28) {
                    Text(shownLanguage.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.cardBackground, in: Capsule())
                    Text(shownText)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Color.appInk)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Label(isFlipped ? "Скрыть перевод" : "Показать перевод",
                          systemImage: isFlipped ? "eye.slash" : "eye")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appAccent)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 14)
                        .background(Color.cardBackground, in: Capsule())
                }
                .padding(24)
                .frame(maxWidth: .infinity, minHeight: 230)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("flashcard")
            .accessibilityHint(isFlipped ? "Вернуться к исходному слову" : "Открыть ответ")

            if shownLanguage == .polish {
                // Keep pronunciation separate from the reveal button.
                PronounceButton(text: shownText, language: .polish)
                    .padding(.bottom, 20)
            }
        }
        .background(Color.appSecondarySurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func gradeButtons(word: Word) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Насколько легко вспомнили?")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.subtleText)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                     count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                ForEach(ReviewGrade.allCases, id: \.self) { grade in
                    Button {
                        apply(grade, to: word)
                    } label: {
                        Text(grade.title)
                            .font(.body.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.vertical, 6)
                            .foregroundStyle(gradeTint(grade))
                            .background(gradeSurface(grade), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func gradeTint(_ grade: ReviewGrade) -> Color {
        switch grade {
        case .again: .appError
        case .hard: .appWarning
        case .good, .easy: .appAccent
        }
    }

    private func gradeSurface(_ grade: ReviewGrade) -> Color {
        switch grade {
        case .again: .appErrorSurface
        case .hard: .appWarningSurface
        case .good, .easy: .appSecondarySurface
        }
    }

    private func apply(_ grade: ReviewGrade, to word: Word) {
        do {
            try dailyStudy.review(grade, to: word, context: modelContext)
        } catch {
            reviewError = error.localizedDescription
            return
        }
        if grade == .again {
            sessionWords.append(word)
        }
        reviewedCount += 1
        // Change the word without a flip that could obscure the next prompt.
        isFlipped = false
        currentIndex += 1
        frontIsRussian = Bool.random()
    }

    private var completedView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.appSuccess)
                    .padding(16)
                    .background(Color.appSecondarySurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                Button("К практике") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.appAccent)
                    .foregroundStyle(Color.appOnAccent)
                    .controlSize(.large)
                    .padding(.top, 8)
            }
            .padding(24)
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

#Preview {
    let resources = AppResources.preview
    NavigationStack {
        FlashcardsView()
    }
    .modelContainer(resources.container)
    .environment(FolderLibraryStore())
    .environment(resources.dailyStudy)
}
