import SwiftUI
import SwiftData

struct QuizView: View {
    var folderID: UUID? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(DailyStudyStore.self) private var dailyStudy
    @Environment(AchievementStore.self) private var achievements
    @Query private var allWords: [Word]

    @State private var questions: [QuizQuestion] = []
    @State private var currentIndex = 0
    @State private var score = 0
    @State private var selectedAnswer: String?
    @State private var quizStarted = false
    @State private var answerError: String?
    @State private var advanceTask: Task<Void, Never>?
    @ScaledMetric(relativeTo: .largeTitle) private var resultIconSize: CGFloat = 40

    private var currentQuestion: QuizQuestion? {
        questions.indices.contains(currentIndex) ? questions[currentIndex] : nil
    }

    var body: some View {
        VStack {
            if let question = currentQuestion {
                questionView(question)
            } else if quizStarted {
                resultView
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .foregroundStyle(Color.appInk)
        .tint(Color.appAccentText)
        .navigationTitle("Викторина")
        .navigationBarTitleDisplayMode(.inline)
        .errorAlert(title: "Не удалось сохранить ответ", error: $answerError)
        .onAppear {
            startQuiz()
            if selectedAnswer != nil { scheduleAdvance() }
        }
        .onDisappear { advanceTask?.cancel() }
        .sensoryFeedback(trigger: selectedAnswer) { _, new -> SensoryFeedback? in
            guard let new else { return nil }
            return new == currentQuestion?.correctAnswer ? .success : .error
        }
    }

    private var feedbackTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
    }

    private func startQuiz() {
        let words = FolderStore.words(allWords, in: folderID)
        guard questions.isEmpty, words.count >= 4 else { return }
        questions = QuizQuestion.generate(from: words, count: 10)
        quizStarted = true
    }

    private func questionView(_ question: QuizQuestion) -> some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                SessionProgress(completed: currentIndex + (selectedAnswer == nil ? 0 : 1), total: questions.count)

                VStack(spacing: AppSpacing.m) {
                    if let word = allWords.first(where: { $0.persistentModelID == question.wordID }) {
                        HStack {
                            Spacer(minLength: 0)
                            KnowledgeTierBadge(word: word,
                                              level: KnowledgeProgressService.tier(for: word),
                                              hidesWordInAccessibilityLabel: question.promptLanguage == .russian)
                        }
                    }
                    Text("Как переводится")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.subtleText)
                    Text(question.prompt)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Color.appInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if question.promptLanguage == .polish {
                        PronounceButton(text: question.prompt, language: .polish)
                    }
                }
                .padding(AppSpacing.xl)
                .frame(maxWidth: .infinity, minHeight: 150)
                .cardStyle(cornerRadius: AppRadius.hero)

                VStack(spacing: AppSpacing.s) {
                    ForEach(question.options, id: \.self) { option in
                        Button {
                            select(option, in: question)
                        } label: {
                            HStack(spacing: 12) {
                                Text(option)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(Color.appInk)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                if selectedAnswer != nil {
                                    if option == question.correctAnswer {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.appMastery)
                                            .transition(feedbackTransition)
                                            .accessibilityLabel("Правильный ответ")
                                    } else if option == selectedAnswer {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(Color.appError)
                                            .transition(feedbackTransition)
                                            .accessibilityLabel("Неверный ответ")
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(optionBackground(option, in: question), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                    .strokeBorder(Color.appBorder, lineWidth: 1)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedAnswer != nil)
                    }
                }
                .animation(.smooth(duration: 0.25), value: selectedAnswer)
            }
            .padding(AppSpacing.l)
        }
    }

    private func optionBackground(_ option: String, in question: QuizQuestion) -> Color {
        guard selectedAnswer != nil else { return .cardBackground }
        if option == question.correctAnswer { return .appMasterySurface }
        if option == selectedAnswer { return .appErrorSurface }
        return .cardBackground
    }

    private func select(_ option: String, in question: QuizQuestion) {
        guard selectedAnswer == nil else { return }
        let isCorrect = option == question.correctAnswer
        guard let word = allWords.first(where: { $0.persistentModelID == question.wordID }) else {
            answerError = "Слово больше не найдено в словаре."
            return
        }
        do {
            try dailyStudy.recordPracticeAnswer(word: word, answer: .choice(isCorrect: isCorrect),
                                                context: modelContext, isQuiz: true)
        } catch {
            answerError = error.localizedDescription
            return
        }
        selectedAnswer = option
        if isCorrect {
            score += 1
        }
        AchievementEvent.quizAnswer(index: currentIndex, count: questions.count, scoreAfter: score,
                                    isCorrect: isCorrect).forEach { achievements.record($0) }
        scheduleAdvance()
    }

    private func scheduleAdvance() {
        advanceTask?.cancel()
        advanceTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(900))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            selectedAnswer = nil
            currentIndex += 1
        }
    }

    private var resultView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: score == questions.count ? "trophy" : "flag.checkered")
                    .font(.system(size: resultIconSize))
                    .fontWeight(.medium)
                    .foregroundStyle(Color.appInk)
                    .padding(AppSpacing.m)
                    .background(Color.appAccentSoft, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
                    .accessibilityHidden(true)
                Text("\(score) из \(questions.count)")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color.appInk)
                    .monospacedDigit()
                Text(resultCaption)
                    .font(.body)
                    .foregroundStyle(Color.subtleText)
                    .multilineTextAlignment(.center)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { resultBadges }
                        .fixedSize(horizontal: true, vertical: false)
                    VStack(spacing: 10) { resultBadges }
                }

                Button {
                    advanceTask?.cancel()
                    questions = []
                    currentIndex = 0
                    score = 0
                    quizStarted = false
                    startQuiz()
                } label: {
                    Text("Ещё раз")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, AppSpacing.xxs)
            }
            .padding(24)
        }
    }

    private var resultBadges: some View {
        Group {
            Label("Верных: \(score)", systemImage: "checkmark")
                .foregroundStyle(Color.appMastery)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.appMasterySurface, in: Capsule())
            Label("Ошибок: \(questions.count - score)", systemImage: "xmark")
                .foregroundStyle(Color.appError)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.appErrorSurface, in: Capsule())
        }
        .font(.subheadline.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
    }

    private var resultCaption: String {
        let ratio = Double(score) / Double(max(questions.count, 1))
        switch ratio {
        case 1: return "Świetnie! Идеально!"
        case 0.7...: return "Отличный результат"
        case 0.4...: return "Неплохо, продолжайте тренироваться"
        default: return "Карточки помогут запомнить лучше"
        }
    }
}

struct QuizQuestion {
    let wordID: PersistentIdentifier
    let prompt: String
    let promptLanguage: AppLanguage
    let correctAnswer: String
    let options: [String]

    static func generate(from words: [Word], count: Int) -> [QuizQuestion] {
        guard words.count >= 4 else { return [] }
        return words.shuffled().prefix(count).compactMap { word in
            let promptLanguage: AppLanguage = Bool.random() ? .russian : .polish
            let answerLanguage = promptLanguage.other
            let correct = word.text(in: answerLanguage)
            // Дедупликация по тексту: слова с одинаковым переводом не должны
            // давать два одинаковых варианта ответа.
            var seen: Set<String> = [correct]
            var distractors: [String] = []
            for candidate in words.shuffled() where distractors.count < 3 {
                guard candidate.persistentModelID != word.persistentModelID else { continue }
                let text = candidate.text(in: answerLanguage)
                if seen.insert(text).inserted {
                    distractors.append(text)
                }
            }
            guard !distractors.isEmpty else { return nil }
            return QuizQuestion(
                wordID: word.persistentModelID,
                prompt: word.text(in: promptLanguage),
                promptLanguage: promptLanguage,
                correctAnswer: correct,
                options: ([correct] + distractors).shuffled()
            )
        }
    }
}

#Preview {
    let resources = AppResources.preview
    NavigationStack {
        QuizView()
    }
    .modelContainer(resources.container)
        .environment(FolderLibraryStore())
        .environment(resources.dailyStudy)
    .environment(resources.achievements)
}
