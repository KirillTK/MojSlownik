import SwiftUI
import SwiftData

struct QuizView: View {
    @Query private var allWords: [Word]

    @State private var questions: [QuizQuestion] = []
    @State private var currentIndex = 0
    @State private var score = 0
    @State private var selectedAnswer: String?
    @State private var quizStarted = false

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
        .navigationTitle("Викторина")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: startQuiz)
    }

    private func startQuiz() {
        guard questions.isEmpty, allWords.count >= 4 else { return }
        questions = QuizQuestion.generate(from: allWords, count: 10)
        quizStarted = true
    }

    private func questionView(_ question: QuizQuestion) -> some View {
        VStack(spacing: 20) {
            ProgressView(value: Double(currentIndex), total: Double(questions.count))
                .tint(.appAccent)

            Text("\(currentIndex + 1) из \(questions.count)")
                .font(.caption)
                .foregroundStyle(Color.subtleText)

            Spacer()

            VStack(spacing: 12) {
                Text("Как переводится")
                    .font(.subheadline)
                    .foregroundStyle(Color.subtleText)
                Text(question.prompt)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                if question.promptLanguage == .polish {
                    PronounceButton(text: question.prompt, language: .polish)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .cardStyle(cornerRadius: 24)

            Spacer()

            VStack(spacing: 10) {
                ForEach(question.options, id: \.self) { option in
                    Button {
                        select(option, in: question)
                    } label: {
                        HStack {
                            Text(option)
                                .font(.body.weight(.medium))
                            Spacer()
                            if selectedAnswer != nil {
                                if option == question.correctAnswer {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else if option == selectedAnswer {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(optionBackground(option, in: question))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedAnswer != nil)
                }
            }
        }
        .padding()
    }

    private func optionBackground(_ option: String, in question: QuizQuestion) -> Color {
        guard selectedAnswer != nil else { return .cardBackground }
        if option == question.correctAnswer { return .green.opacity(0.15) }
        if option == selectedAnswer { return .red.opacity(0.15) }
        return .cardBackground
    }

    private func select(_ option: String, in question: QuizQuestion) {
        selectedAnswer = option
        if option == question.correctAnswer {
            score += 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            selectedAnswer = nil
            currentIndex += 1
        }
    }

    private var resultView: some View {
        VStack(spacing: 16) {
            Image(systemName: score == questions.count ? "trophy.fill" : "flag.checkered")
                .font(.system(size: 56))
                .foregroundStyle(score == questions.count ? .yellow : Color.appAccent)
            Text("\(score) из \(questions.count)")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
            Text(resultCaption)
                .foregroundStyle(Color.subtleText)

            Button {
                questions = []
                currentIndex = 0
                score = 0
                quizStarted = false
                startQuiz()
            } label: {
                Text("Ещё раз")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(Color.appAccent)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .padding(.top, 8)
        }
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
                prompt: word.text(in: promptLanguage),
                promptLanguage: promptLanguage,
                correctAnswer: correct,
                options: ([correct] + distractors).shuffled()
            )
        }
    }
}

#Preview {
    NavigationStack {
        QuizView()
    }
    .modelContainer(for: Word.self, inMemory: true)
}
