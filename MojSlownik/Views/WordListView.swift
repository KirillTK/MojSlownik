import SwiftUI
import SwiftData

struct WordListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Word.createdAt, order: .reverse) private var words: [Word]

    @State private var searchText = ""
    @State private var showAddSheet = false
    @State private var showScanner = false
    @State private var scannedPrefill: ScannedText?

    private var filteredWords: [Word] {
        guard !searchText.isEmpty else { return words }
        let query = searchText.lowercased()
        return words.filter {
            $0.russian.lowercased().contains(query) || $0.polish.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if words.isEmpty {
                    ContentUnavailableView {
                        Label("Словарь пуст", systemImage: "character.book.closed")
                    } description: {
                        Text("Добавьте первое слово кнопкой «плюс» или отсканируйте его камерой.")
                    }
                } else {
                    List {
                        ForEach(filteredWords) { word in
                            WordRow(word: word)
                                .listRowBackground(Color.cardBackground)
                        }
                        .onDelete(perform: deleteWords)
                    }
                    .scrollContentBackground(.hidden)
                    .searchable(text: $searchText, prompt: "Поиск слова")
                }
            }
            .background(Color.appBackground)
            .navigationTitle("Mój Słownik")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "camera.viewfinder")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddWordView()
            }
            .sheet(item: $scannedPrefill) { scanned in
                AddWordView(initialText: scanned.text)
            }
            .fullScreenCover(isPresented: $showScanner) {
                ScannerScreen { text in
                    showScanner = false
                    // Небольшая задержка, чтобы fullScreenCover успел закрыться до открытия sheet.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        scannedPrefill = ScannedText(text: text)
                    }
                }
            }
        }
    }

    private func deleteWords(at offsets: IndexSet) {
        // Снимок до удаления: filteredWords пересчитывается после каждого delete.
        let wordsToDelete = offsets.map { filteredWords[$0] }
        for word in wordsToDelete {
            modelContext.delete(word)
        }
    }
}

struct ScannedText: Identifiable {
    let id = UUID()
    let text: String
}

private struct WordRow: View {
    let word: Word

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(word.polish)
                    .font(.body.weight(.semibold))
                Text(word.russian)
                    .font(.subheadline)
                    .foregroundStyle(Color.subtleText)
            }
            Spacer()
            PronounceButton(text: word.polish, language: .polish)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    WordListView()
        .modelContainer(for: Word.self, inMemory: true)
}
