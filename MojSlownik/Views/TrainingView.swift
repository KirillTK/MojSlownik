import SwiftUI
import SwiftData

struct TrainingView: View {
    @Environment(DailyStudyStore.self) private var dailyStudy
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var allWords: [Word]
    @State private var selectedFolderID: UUID?
    @State private var refreshDate = Date.now

    private var words: [Word] { FolderStore.words(allWords, in: selectedFolderID) }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                let now = max(timeline.date, refreshDate)
                let progress = dailyStudy.progress(for: words, now: now)
                let answers = dailyStudy.answerTotals(for: words, now: now)
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        FolderPicker(selectedFolderID: $selectedFolderID, allowsAll: true)
                        heading(progress: progress)
                        reviewProgress(progress, answers: answers)
                        answerStatistics(answers)
                        practiceButton(progress: progress)
                        libraryAndQuiz
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .background(Color.appBackground)
            .foregroundStyle(Color.appInk)
            .navigationTitle("Тренировка")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { refreshClock() }
            .onChange(of: scenePhase) {
                if scenePhase == .active { refreshClock() }
            }
        }
    }

    private func refreshClock() {
        refreshDate = .now
        dailyStudy.refresh(now: refreshDate)
    }

    private func heading(progress: DailyStudyStore.Summary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Сегодня")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.subtleText)
            Text(words.isEmpty ? "Начнём со слова." : progress.remaining == 0 ? "Можно выдохнуть." : "В своём темпе.")
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(words.isEmpty
                 ? "Добавьте слова в словарь, чтобы начать тренировку."
                 : progress.remaining == 0
                    ? "Сейчас нет слов, требующих повторения."
                    : "Каждое повторение помогает запомнить больше.")
                .font(.body)
                .foregroundStyle(Color.subtleText)
        }
    }

    private func reviewProgress(_ progress: DailyStudyStore.Summary, answers: DailyStudyStore.AnswerTotals) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.appSecondarySurface, lineWidth: 14)
                Circle()
                    .trim(from: 0, to: CGFloat(progress.fraction))
                    .stroke(Color.appAccent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: progress.total > 0 && progress.remaining == 0 ? "checkmark" : "leaf")
                        .font(.largeTitle)
                        .foregroundStyle(Color.appAccent)
                } else {
                    VStack(spacing: 6) {
                        Text("\(progress.completed) / \(progress.total)")
                            .font(.title.weight(.bold))
                            .monospacedDigit()
                        Text("повторено")
                            .font(.subheadline)
                            .foregroundStyle(Color.subtleText)
                    }
                }
            }
            .frame(width: 196, height: 196)
            .padding(8)
            .accessibilityHidden(true)

            if dynamicTypeSize.isAccessibilitySize {
                Text("Повторено сегодня: \(progress.completed) из \(progress.total)")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            Text(answers.total > 0 && answers.correct == 0
                 ? "Пока нет верных ответов"
                 : progress.total == 0 ? "Повторений сегодня ещё не было" : "Повторено сегодня: \(progress.completed)")
                .font(.subheadline)
                .foregroundStyle(Color.subtleText)
            Text(words.isEmpty ? "Добавьте первое слово" : progress.remaining > 0 ? "Осталось повторить: \(progress.remaining)" : progress.completed > 0 ? "Все текущие повторения завершены" : "Можно потренироваться без спешки")
                .font(.body.weight(.medium))
                .multilineTextAlignment(.center)
            Text("Объём обновляется, когда появляются новые слова к повторению.")
                .font(.caption)
                .foregroundStyle(Color.subtleText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Повторено сегодня: \(progress.completed) из \(progress.total). Осталось повторить: \(progress.remaining).")
    }

    private func answerStatistics(_ answers: DailyStudyStore.AnswerTotals) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ответов сегодня: \(answers.total)")
                .font(.subheadline.weight(.medium))
            Text("Верных: \(answers.correct) · Ошибок: \(answers.incorrect)")
                .font(.subheadline)
                .foregroundStyle(Color.subtleText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func practiceButton(progress: DailyStudyStore.Summary) -> some View {
        NavigationLink {
            FlashcardsView(folderID: selectedFolderID)
        } label: {
            Text(progress.remaining > 0
                 ? progress.completed == 0 ? "Начать повторение · \(progress.remaining)" : "Продолжить · \(progress.remaining)"
                 : "Свободная практика")
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 24)
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
                .foregroundStyle(Color.appOnAccent)
                .background(words.isEmpty ? Color.subtleText : Color.appAccent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(words.isEmpty)
        .accessibilityHint(progress.remaining > 0 ? "Открыть карточки для повторения" : "Потренировать до десяти случайных слов")
    }

    private var libraryAndQuiz: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Слов в выбранном наборе: \(words.count)", systemImage: "book.closed")
                .font(.subheadline)
                .foregroundStyle(Color.subtleText)
            Divider().overlay(Color.appBorder.opacity(0.5))
            NavigationLink {
                QuizView(folderID: selectedFolderID)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "checklist")
                        .font(.title3)
                        .foregroundStyle(Color.appAccent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Викторина")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.appInk)
                        Text(words.count >= 4 ? "Выберите правильный перевод" : "Нужно минимум 4 слова в выбранном наборе")
                            .font(.subheadline)
                            .foregroundStyle(Color.subtleText)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.subtleText)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(words.count < 4)
        }
    }
}

#Preview {
    TrainingView()
        .modelContainer(for: [Word.self, WordFolder.self], inMemory: true)
        .environment(FolderLibraryStore())
        .environment(DailyStudyStore())
}
