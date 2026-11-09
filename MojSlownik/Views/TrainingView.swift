import SwiftUI
import SwiftData

struct TrainingView: View {
    @Query private var allWords: [Word]
    @State private var selectedFolderID: UUID?

    private var words: [Word] { FolderStore.words(allWords, in: selectedFolderID) }

    private var dueCount: Int {
        words.filter(\.isDue).count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    FolderPicker(selectedFolderID: $selectedFolderID, allowsAll: true)
                    statsCard

                    NavigationLink {
                        FlashcardsView(folderID: selectedFolderID)
                    } label: {
                        TrainingModeCard(
                            icon: "rectangle.portrait.on.rectangle.portrait.angled",
                            title: "Флешкарточки",
                            subtitle: dueCount > 0
                                ? "К повторению: \(dueCount)"
                                : "Пока нечего повторять",
                            badge: dueCount > 0 ? "\(dueCount)" : nil
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(words.isEmpty)

                    NavigationLink {
                        QuizView(folderID: selectedFolderID)
                    } label: {
                        TrainingModeCard(
                            icon: "checklist",
                            title: "Викторина",
                            subtitle: words.count >= 4
                                ? "Выберите правильный перевод из четырёх"
                                : "Нужно минимум 4 слова в словаре",
                            badge: nil
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(words.count < 4)
                }
                .padding()
            }
            .background(Color.appBackground)
            .navigationTitle("Тренировка")
        }
    }

    private var statsCard: some View {
        HStack(spacing: 0) {
            StatItem(value: "\(words.count)", label: "слов")
            Divider().frame(height: 36)
            StatItem(value: "\(dueCount)", label: "к повторению")
            Divider().frame(height: 36)
            StatItem(value: "\(words.filter { $0.repetitions >= 3 }.count)", label: "выучено")
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }
}

private struct StatItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.appAccent)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.subtleText)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TrainingModeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let badge: String?

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.appAccent)
                .frame(width: 48, height: 48)
                .background(Color.appAccent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.subtleText)
            }

            Spacer()

            if let badge {
                Text(badge)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.appAccent)
                    .foregroundStyle(Color.appOnAccent)
                    .clipShape(Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.subtleText)
        }
        .padding(16)
        .cardStyle()
    }
}

#Preview {
    TrainingView()
        .modelContainer(for: [Word.self, WordFolder.self], inMemory: true)
        .environment(FolderLibraryStore())
}
