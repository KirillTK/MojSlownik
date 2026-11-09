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
                    VStack(alignment: .leading, spacing: 20) {
                        FolderPicker(selectedFolderID: $selectedFolderID, allowsAll: true, compact: true)
                        todayPanel(progress: progress, answers: answers)
                        modes
                        practiceButton(progress: progress)
                        Text("Слов в выбранном наборе: \(words.count)")
                            .font(.footnote)
                            .foregroundStyle(Color.subtleText)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .background(Color.appBackground)
            .foregroundStyle(Color.appInk)
            .navigationTitle("Практика")
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

    private func todayPanel(progress: DailyStudyStore.Summary, answers: DailyStudyStore.AnswerTotals) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return VStack(alignment: .leading, spacing: 12) {
            layout {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Сегодня")
                        .font(.subheadline.weight(.medium))
                    Text(words.isEmpty ? "Добавьте первое слово" : progress.total > 0 ? "\(progress.completed) из \(progress.total)" : "Нет повторений")
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text(words.isEmpty ? "Начните со словаря" : progress.remaining > 0 ? "Осталось слов: \(progress.remaining)" : progress.completed > 0 ? "Всё повторено" : "Доступна свободная практика")
                    .font(.subheadline)
                    .foregroundStyle(Color.subtleText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ProgressView(value: progress.fraction)
                .tint(.appAccent)
                .accessibilityLabel("Повторено сегодня")
                .accessibilityValue("\(progress.completed) из \(progress.total). Осталось: \(progress.remaining)")
            layout {
                answerBadge(count: answers.correct, title: "Верных", icon: "checkmark", foreground: .appAccent, background: .cardBackground)
                answerBadge(count: answers.incorrect, title: "Ошибок", icon: "xmark", foreground: .appError, background: .appErrorSurface)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            }
            Text("Ответов: \(answers.total)")
                .font(.caption)
                .foregroundStyle(Color.subtleText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSecondarySurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func answerBadge(count: Int, title: String, icon: String, foreground: Color, background: Color) -> some View {
        Label("\(title): \(count)", systemImage: icon)
            .font(.subheadline.weight(.medium))
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(background, in: Capsule())
    }

    private var modes: some View {
        VStack(spacing: 0) {
            NavigationLink {
                FlashcardsView(folderID: selectedFolderID)
            } label: {
                modeRow(title: "Карточки", subtitle: "Вспомнить перевод", icon: "rectangle.on.rectangle.angled")
            }
            .disabled(words.isEmpty)
            Divider().overlay(Color.appBorder.opacity(0.5))
            NavigationLink {
                QuizView(folderID: selectedFolderID)
            } label: {
                modeRow(title: "Викторина", subtitle: words.count >= 4 ? "Выбрать правильный ответ" : "Нужно минимум 4 слова", icon: "checklist")
            }
            .disabled(words.count < 4)
        }
        .buttonStyle(.plain)
    }

    private func modeRow(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.appAccent)
                .frame(width: 44, height: 44)
                .background(Color.appSecondarySurface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(Color.appInk)
                Text(subtitle).font(.subheadline).foregroundStyle(Color.subtleText)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.subtleText)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 14)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
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
                .padding(16)
                .foregroundStyle(Color.appOnAccent)
                .background(words.isEmpty ? Color.subtleText : Color.appAccent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(words.isEmpty)
        .accessibilityHint(progress.remaining > 0 ? "Открыть карточки для повторения" : "Потренировать до десяти случайных слов")
    }
}

#Preview {
    let resources = AppResources.preview
    TrainingView()
        .modelContainer(resources.container)
        .environment(FolderLibraryStore())
        .environment(resources.dailyStudy)
}
