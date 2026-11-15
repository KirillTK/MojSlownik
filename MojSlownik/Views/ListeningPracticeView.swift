import SwiftUI
import SwiftData

struct ListeningPracticeView: View {
    var folderID: UUID? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(DailyStudyStore.self) private var dailyStudy
    @Query private var allWords: [Word]

    @State private var questions: [ListeningQuestion] = []
    @State private var currentIndex = 0
    @State private var score = 0
    @State private var answer = ""
    @State private var submittedAnswer: String?
    @State private var answerIsCorrect: Bool?
    @State private var sessionStarted = false
    @State private var answerError: String?
    @State private var advanceTask: Task<Void, Never>?
    @FocusState private var answerFocused: Bool

    private var currentQuestion: ListeningQuestion? {
        questions.indices.contains(currentIndex) ? questions[currentIndex] : nil
    }

    var body: some View {
        Group {
            if let question = currentQuestion {
                questionView(question)
            } else if sessionStarted {
                resultView
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .foregroundStyle(Color.appInk)
        .tint(Color.appAccent)
        .navigationTitle("На слух")
        .navigationBarTitleDisplayMode(.inline)
        .errorAlert(title: "Не удалось сохранить ответ", error: $answerError)
        .onAppear {
            startSession()
            if answerIsCorrect == true { scheduleAdvance() }
        }
        .onDisappear {
            advanceTask?.cancel()
            SpeechService.shared.stop()
        }
    }

    private func startSession() {
        let words = FolderStore.words(allWords, in: folderID)
        guard questions.isEmpty, !words.isEmpty else { return }
        dailyStudy.refresh()
        questions = ListeningQuestion.generate(from: words, count: 10)
        sessionStarted = true
        speakCurrentQuestion()
    }

    private func questionView(_ question: ListeningQuestion) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                SessionProgress(completed: currentIndex + (submittedAnswer == nil ? 0 : 1), total: questions.count)

                VStack(spacing: 16) {
                    Text(promptTitle(for: question.mode))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.subtleText)
                    if question.mode == .translation {
                        Text(question.prompt)
                            .font(.title.weight(.bold))
                            .foregroundStyle(Color.appInk)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if question.mode != .translation {
                        replayButton
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, minHeight: 150)
                .background(Color.appSecondarySurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                if question.mode == .choices {
                    choiceAnswers(question)
                } else {
                    spellingAnswer(question)
                }

                if let submittedAnswer {
                    feedbackView(for: question, submittedAnswer: submittedAnswer)
                    Button {
                        advanceTask?.cancel()
                        advanceToNextQuestion()
                    } label: {
                        Text(currentIndex == questions.count - 1 ? "К результатам" : "Дальше")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.vertical, 6)
                            .foregroundStyle(Color.appOnAccent)
                            .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func promptTitle(for mode: ListeningAnswerMode) -> String {
        switch mode {
        case .choices: "Прослушайте и выберите польское слово"
        case .translation: "Введите перевод на польский"
        case .dictation: "Прослушайте и напишите слово"
        }
    }

    private var replayButton: some View {
        Button {
            speakCurrentQuestion()
        } label: {
            Label("Повторить", systemImage: "speaker.wave.2.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.appAccent)
                .frame(minHeight: 44)
                .padding(.horizontal, 14)
                .background(Color.cardBackground, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Повторить произношение")
    }

    private func choiceAnswers(_ question: ListeningQuestion) -> some View {
        VStack(spacing: 10) {
            ForEach(question.options, id: \.self) { option in
                Button {
                    submit(option, for: question)
                } label: {
                    HStack(spacing: 12) {
                        Text(option)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.appInk)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if submittedAnswer != nil {
                            if option == question.correctAnswer {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.appSuccess)
                                    .accessibilityLabel("Правильный ответ")
                            } else if option == submittedAnswer {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Color.appError)
                                    .accessibilityLabel("Неверный ответ")
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(optionBackground(option, in: question), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.appBorder.opacity(0.5), lineWidth: 0.5)
                    }
                }
                .buttonStyle(.plain)
                .disabled(submittedAnswer != nil)
            }
        }
    }

    private func optionBackground(_ option: String, in question: ListeningQuestion) -> Color {
        guard submittedAnswer != nil else { return .cardBackground }
        if option == question.correctAnswer { return .appSecondarySurface }
        if option == submittedAnswer { return .appErrorSurface }
        return .cardBackground
    }

    private func spellingAnswer(_ question: ListeningQuestion) -> some View {
        VStack(spacing: 12) {
            TextField("Польское слово", text: $answer)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($answerFocused)
                .onSubmit { submit(answer, for: question) }
                .padding(16)
                .frame(minHeight: 52)
                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.appBorder.opacity(0.5), lineWidth: 0.5)
                }
                .disabled(submittedAnswer != nil)
                .accessibilityIdentifier("listeningAnswer")

            Button {
                submit(answer, for: question)
            } label: {
                Text("Проверить")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.vertical, 6)
                    .foregroundStyle(Color.appOnAccent)
                    .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(submittedAnswer != nil || answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func feedbackView(for question: ListeningQuestion, submittedAnswer: String) -> some View {
        VStack(spacing: 6) {
            Text(answerIsCorrect == true ? "Верно!" : "Правильный ответ: \(question.correctAnswer)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(answerIsCorrect == true ? Color.appSuccess : Color.appError)
                .multilineTextAlignment(.center)
            if answerIsCorrect == false && question.mode != .choices {
                Text("Ваш ответ: \(submittedAnswer)")
                    .font(.caption)
                    .foregroundStyle(Color.subtleText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(answerIsCorrect == true ? Color.appSecondarySurface : Color.appErrorSurface,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func submit(_ answer: String, for question: ListeningQuestion) {
        guard submittedAnswer == nil else { return }
        answerFocused = false
        guard let word = allWords.first(where: { $0.persistentModelID == question.wordID }) else {
            answerError = "Слово больше не найдено в словаре."
            return
        }
        let knowledgeAnswer: KnowledgeAnswer = question.mode == .choices
            ? .choice(isCorrect: answer == question.correctAnswer)
            : .typed(expected: question.correctAnswer, submitted: answer)
        let isCorrect = KnowledgeProgressService.isCorrect(knowledgeAnswer)
        do {
            try dailyStudy.recordPracticeAnswer(word: word, answer: knowledgeAnswer,
                                                context: modelContext, isQuiz: true)
        } catch {
            answerError = error.localizedDescription
            return
        }
        submittedAnswer = answer
        answerIsCorrect = isCorrect
        if isCorrect { score += 1 }
        if isCorrect { scheduleAdvance() }
    }

    private func speakCurrentQuestion() {
        guard let question = currentQuestion, question.mode != .translation else { return }
        SpeechService.shared.speak(question.correctAnswer, language: .polish)
    }

    private func scheduleAdvance() {
        advanceTask?.cancel()
        advanceTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(4))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            advanceToNextQuestion()
        }
    }

    private func advanceToNextQuestion() {
        guard submittedAnswer != nil else { return }
        submittedAnswer = nil
        answerIsCorrect = nil
        answer = ""
        currentIndex += 1
        speakCurrentQuestion()
    }

    private var resultView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: score == questions.count ? "trophy.fill" : "flag.checkered")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.appAccent)
                    .padding(16)
                    .background(Color.appSecondarySurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                    sessionStarted = false
                    startSession()
                } label: {
                    Text("Ещё раз")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.vertical, 6)
                        .foregroundStyle(Color.appOnAccent)
                        .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(24)
        }
    }

    private var resultBadges: some View {
        Group {
            Label("Верных: \(score)", systemImage: "checkmark")
                .foregroundStyle(Color.appSuccess)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.appSecondarySurface, in: Capsule())
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
        return switch ratio {
        case 1: "Отлично! Идеально!"
        case 0.7...: "Отличный результат"
        case 0.4...: "Неплохо, продолжайте тренироваться"
        default: "Карточки помогут запомнить лучше"
        }
    }
}

#Preview {
    let resources = AppResources.preview
    NavigationStack {
        ListeningPracticeView()
    }
    .modelContainer(resources.container)
    .environment(FolderLibraryStore())
    .environment(resources.dailyStudy)
}
