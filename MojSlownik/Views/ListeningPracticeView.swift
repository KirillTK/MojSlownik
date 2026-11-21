import SwiftUI
import SwiftData

struct ListeningPracticeView: View {
    var folderID: UUID? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(WorkspaceStore.self) private var workspaces
    @Environment(DailyStudyStore.self) private var dailyStudy
    @Environment(AchievementStore.self) private var achievements
    @Query private var storedAllWords: [Word]
    @Query private var storedMemberships: [FolderMembership]
    private var memberships: MembershipIndex { MembershipIndex(storedMemberships) }
    private var allWords: [Word] { WorkspaceScope.words(storedAllWords, workspaceID: workspaces.activeID) }

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
    @ScaledMetric(relativeTo: .largeTitle) private var resultIconSize: CGFloat = 40
    @ScaledMetric(relativeTo: .title) private var replaySize: CGFloat = 64

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
        .tint(Color.appAccentText)
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
        .sensoryFeedback(trigger: answerIsCorrect) { _, new -> SensoryFeedback? in
            guard let new else { return nil }
            return new ? .success : .error
        }
    }

    private var feedbackTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
    }

    private func startSession() {
        let words = FolderStore.words(allWords, in: folderID, memberships: memberships)
        guard questions.isEmpty, !words.isEmpty else { return }
        dailyStudy.refresh()
        questions = ListeningQuestion.generate(from: words, count: 10)
        sessionStarted = true
        speakCurrentQuestion()
    }

    private func questionView(_ question: ListeningQuestion) -> some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                SessionProgress(completed: currentIndex + (submittedAnswer == nil ? 0 : 1), total: questions.count)

                VStack(spacing: AppSpacing.m) {
                    if let word = allWords.first(where: { $0.persistentModelID == question.wordID }) {
                        HStack {
                            Spacer(minLength: 0)
                            KnowledgeTierBadge(word: word,
                                              level: KnowledgeProgressService.tier(for: word),
                                              hidesWordInAccessibilityLabel: true)
                        }
                    }
                    Text(promptTitle(for: question.mode))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.subtleText)
                    if question.mode == .translation {
                        Text(question.prompt)
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Color.appInk)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if question.mode != .translation {
                        replayButton
                    }
                }
                .padding(AppSpacing.xl)
                .frame(maxWidth: .infinity, minHeight: 150)
                .cardStyle(cornerRadius: AppRadius.hero)

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
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.25), value: submittedAnswer)
            .padding(AppSpacing.l)
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
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: "speaker.wave.2")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.appInk)
                    .frame(width: replaySize, height: replaySize)
                    .background(Color.appAccentSoft, in: Circle())
                Text("Повторить")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.subtleText)
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Повторить произношение")
    }

    private func choiceAnswers(_ question: ListeningQuestion) -> some View {
        VStack(spacing: AppSpacing.s) {
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
                                    .foregroundStyle(Color.appMastery)
                                    .transition(feedbackTransition)
                                    .accessibilityLabel("Правильный ответ")
                            } else if option == submittedAnswer {
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
                .disabled(submittedAnswer != nil)
            }
        }
    }

    private func optionBackground(_ option: String, in question: ListeningQuestion) -> Color {
        guard submittedAnswer != nil else { return .cardBackground }
        if option == question.correctAnswer { return .appMasterySurface }
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
                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .strokeBorder(answerFocused ? Color.appAccentStrong : Color.appBorder,
                                      lineWidth: answerFocused ? 2 : 1)
                }
                .disabled(submittedAnswer != nil)
                .accessibilityIdentifier("listeningAnswer")

            Button {
                submit(answer, for: question)
            } label: {
                Text("Проверить")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(submittedAnswer != nil || answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func feedbackView(for question: ListeningQuestion, submittedAnswer: String) -> some View {
        VStack(spacing: 6) {
            Label(answerIsCorrect == true ? "Верно!" : "Правильный ответ: \(question.correctAnswer)",
                  systemImage: answerIsCorrect == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(answerIsCorrect == true ? Color.appMastery : Color.appError)
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
        .background(answerIsCorrect == true ? Color.appMasterySurface : Color.appErrorSurface,
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .accessibilityElement(children: .combine)
        .transition(feedbackTransition)
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
                                                context: modelContext, mode: .listening)
        } catch {
            answerError = error.localizedDescription
            return
        }
        submittedAnswer = answer
        answerIsCorrect = isCorrect
        if isCorrect { score += 1 }
        achievements.record(.answer(mode: .listening, isCorrect: isCorrect))
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
                    sessionStarted = false
                    startSession()
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
    .environment(resources.workspaces)
    .environment(resources.folders)
    .environment(resources.vocabulary)
    .environment(resources.dailyStudy)
    .environment(resources.achievements)
}
