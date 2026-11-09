import SwiftUI
import SwiftData

struct FlashcardsView: View {
    var folderID: UUID? = nil
    @Environment(\.modelContext) private var modelContext
    @Query private var allWords: [Word]

    @State private var sessionWords: [Word] = []
    @State private var currentIndex = 0
    @State private var isFlipped = false
    @State private var reviewedCount = 0
    @State private var sessionStarted = false
    // Направление карточки: true = показываем русское, вспоминаем польское.
    @State private var frontIsRussian = Bool.random()

    private var currentWord: Word? {
        sessionWords.indices.contains(currentIndex) ? sessionWords[currentIndex] : nil
    }

    var body: some View {
        VStack {
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
        .onAppear(perform: startSession)
    }

    private func startSession() {
        let words = FolderStore.words(allWords, in: folderID)
        guard sessionWords.isEmpty, !words.isEmpty else { return }
        let due = words.filter(\.isDue).shuffled()
        // Если повторять нечего — даём потренировать 10 случайных слов.
        sessionWords = due.isEmpty ? Array(words.shuffled().prefix(10)) : due
        sessionStarted = true
    }

    private func sessionView(word: Word) -> some View {
        VStack(spacing: 24) {
            SessionProgress(completed: reviewedCount, total: sessionWords.count, spacing: 24)
                .padding(.horizontal)

            Spacer()

            card(word: word)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(duration: 0.45)) {
                        isFlipped.toggle()
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("flashcard")

            Spacer()

            if isFlipped {
                gradeButtons(word: word)
            } else {
                Text("Коснитесь карточки, чтобы увидеть перевод")
                    .font(.footnote)
                    .foregroundStyle(Color.subtleText)
                    .padding(.bottom, 24)
            }
        }
        .padding()
    }

    private func card(word: Word) -> some View {
        let frontLanguage: AppLanguage = frontIsRussian ? .russian : .polish
        let shownLanguage = isFlipped ? frontLanguage.other : frontLanguage
        let shownText = word.text(in: shownLanguage)

        return VStack(spacing: 16) {
            Text("\(shownLanguage.flag) \(shownLanguage.displayName)")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.subtleText)

            Text(shownText)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)

            if shownLanguage == .polish {
                PronounceButton(text: shownText, language: .polish)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: 260)
        .cardStyle(cornerRadius: 28)
        .rotation3DEffect(.degrees(isFlipped ? 360 : 0), axis: (x: 0, y: 1, z: 0))
        .padding(.horizontal, 8)
    }

    private func gradeButtons(word: Word) -> some View {
        HStack(spacing: 10) {
            ForEach(ReviewGrade.allCases, id: \.self) { grade in
                Button {
                    apply(grade, to: word)
                } label: {
                    Text(grade.title)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(grade.color.opacity(0.14))
                        .foregroundStyle(grade.color)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .padding(.bottom, 12)
    }

    private func apply(_ grade: ReviewGrade, to word: Word) {
        SRSEngine.apply(grade, to: word)
        // «Не помню» — карточка вернётся ещё раз в конце этой же сессии.
        if grade == .again {
            sessionWords.append(word)
        }
        reviewedCount += 1
        withAnimation(.easeInOut(duration: 0.25)) {
            isFlipped = false
            currentIndex += 1
            frontIsRussian = Bool.random()
        }
    }

    private var completedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Готово!")
                .font(.title.weight(.bold))
            Text("Повторено слов: \(reviewedCount)")
                .foregroundStyle(Color.subtleText)
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
}
