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
        .navigationTitle("Флешкарточки")
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
            VStack(spacing: 28) {
                SessionProgress(completed: reviewedCount, total: sessionWords.count, spacing: 10)
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

        return VStack(spacing: 20) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    isFlipped.toggle()
                }
            } label: {
                VStack(spacing: 24) {
                    Text(shownLanguage.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.subtleText)
                    Text(shownText)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Color.appInk)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Label(isFlipped ? "Скрыть перевод" : "Показать перевод",
                          systemImage: isFlipped ? "eye.slash" : "eye")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.appAccent)
                        .frame(minHeight: 44)
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
        .cardStyle(cornerRadius: 24)
    }

    private func gradeButtons(word: Word) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 8))
        return VStack(alignment: .leading, spacing: 12) {
            Text("Насколько легко вспомнили?")
                .font(.subheadline)
                .foregroundStyle(Color.subtleText)
            layout {
                ForEach(ReviewGrade.allCases, id: \.self) { grade in
                    Button {
                        apply(grade, to: word)
                    } label: {
                        Text(grade.title)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.vertical, 4)
                            .background(grade.color.opacity(0.12))
                            .foregroundStyle(grade.color)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
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
                    .font(.system(size: 64))
                    .foregroundStyle(Color.appSuccess)
                Text("Тренировка завершена")
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Повторено слов: \(Set(sessionWords.map(\.persistentModelID)).count)")
                    .font(.title3.weight(.medium))
                Text("Всего ответов: \(reviewedCount)")
                    .foregroundStyle(Color.subtleText)
                Button("К тренировкам") { dismiss() }
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
    NavigationStack {
        FlashcardsView()
    }
    .modelContainer(for: [Word.self, WordFolder.self], inMemory: true)
    .environment(FolderLibraryStore())
    .environment(DailyStudyStore())
}
