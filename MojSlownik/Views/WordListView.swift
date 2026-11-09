import SwiftUI
import SwiftData

struct WordListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Word.createdAt, order: .reverse) private var words: [Word]

    @Environment(FolderLibraryStore.self) private var folderLibrary
    @State private var selectedFolderID: UUID?
    @State private var showDeleteFolder = false
    @State private var folderError: String?
    @State private var selectedCategory: WordCategory?
    @State private var searchText = ""
    @State private var showAddSheet = false
    @State private var showScanner = false
    @State private var scannedResult: ScannedText?
    @State private var didHandleTestPrefill = false

    private var filteredWords: [Word] {
        let query = searchText.lowercased()
        return FolderStore.words(words, in: selectedFolderID).filter { word in
            (selectedCategory == nil || word.category == selectedCategory)
                && (query.isEmpty || word.russian.lowercased().contains(query)
                    || word.polish.lowercased().contains(query))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryFilters
                Group {
                if words.isEmpty {
                    ContentUnavailableView {
                        Label("Словарь пуст", systemImage: "character.book.closed")
                    } description: {
                        Text("Добавьте первое слово кнопкой «плюс» или отсканируйте его камерой.")
                    }
                } else {
                    VStack(spacing: 0) {
                        List {
                            if filteredWords.isEmpty {
                                ContentUnavailableView {
                                    Label("Нет подходящих слов", systemImage: "magnifyingglass")
                                } description: {
                                    Text("Проверьте выбранную папку, категорию и поисковый запрос.")
                                } actions: {
                                    Button("Показать все слова") {
                                        selectedFolderID = nil
                                        selectedCategory = nil
                                        searchText = ""
                                    }
                                }
                                .listRowBackground(Color.clear)
                            }
                            ForEach(filteredWords) { word in
                                WordRow(word: word)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                                    .listRowSeparatorTint(Color.appBorder.opacity(0.5))
                            }
                            .onDelete(perform: deleteWords)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                    .searchable(text: $searchText, prompt: "Найти слово")
                }
            }
            }
            .background(Color.appBackground)
            .foregroundStyle(Color.appInk)
            .navigationTitle("Словарь")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if selectedFolderID != nil {
                        Button("Удалить папку", systemImage: "folder.badge.minus") { showDeleteFolder = true }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "camera.viewfinder")
                            .frame(minWidth: 44, minHeight: 44)
                            .background(Color.appSecondarySurface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .accessibilityLabel("Сканировать текст")
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(Color.appSecondarySurface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .accessibilityLabel("Добавить слово")
                }
            }
            .confirmationDialog("Удалить папку? Слова останутся в словаре.", isPresented: $showDeleteFolder, titleVisibility: .visible) {
                Button("Удалить папку", role: .destructive) {
                    guard let id = selectedFolderID else { return }
                    do {
                        try folderLibrary.delete(id: id, context: modelContext)
                        selectedFolderID = nil
                    } catch { folderError = error.localizedDescription }
                }
            }
            .errorAlert(title: "Не удалось изменить папку", error: $folderError)
            .sheet(isPresented: $showAddSheet) {
                AddWordView(initialFolderID: selectedFolderID)
            }
            .sheet(item: $scannedResult) { scanned in
                ScanResultView(scannedText: scanned.text)
            }
            .fullScreenCover(isPresented: $showScanner) {
                ScannerScreen { text in
                    showScanner = false
                    // Небольшая задержка, чтобы fullScreenCover успел закрыться до открытия sheet.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        scannedResult = ScannedText(text: text)
                    }
                }
            }
            .onAppear {
                // Вход для UI-тестов: имитирует префилл из сканера (ввод кириллицы
                // с тестовой клавиатуры ненадёжен).
                if !didHandleTestPrefill,
                   let prefill = ProcessInfo.processInfo.environment["UITEST_PREFILL"] {
                    didHandleTestPrefill = true
                    scannedResult = ScannedText(text: prefill)
                }
            }
        }
    }

    private var categoryFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FolderPicker(selectedFolderID: $selectedFolderID, allowsAll: true, compact: true)
                Rectangle()
                    .fill(Color.appBorder)
                    .frame(width: 1, height: 24)
                    .padding(.horizontal, 4)
                    .accessibilityHidden(true)
                categoryFilter(nil, title: "Все темы", count: FolderStore.words(words, in: selectedFolderID).count)
                ForEach(WordCategory.allCases) { category in
                    let count = FolderStore.words(words, in: selectedFolderID).filter { $0.category == category }.count
                    if count > 0 || selectedCategory == category {
                        categoryFilter(category, title: category.rawValue, count: count)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .accessibilityLabel("Папка и фильтр по теме")
    }

    private func categoryFilter(_ category: WordCategory?, title: String, count: Int) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .fontWeight(isSelected ? .semibold : .medium)
                Text(count.formatted())
                    .monospacedDigit()
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .foregroundStyle(isSelected ? Color.appOnAccent : Color.appInk)
            .background(isSelected ? Color.appAccent : Color.cardBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), слов: \(count)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @Environment(FolderLibraryStore.self) private var folderLibrary
    @State private var folderError: String?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 12) {
                    wordText.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    wordActions.fixedSize(horizontal: true, vertical: false)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                wordText
                wordActions.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
        .errorAlert(title: "Не удалось изменить папку", error: $folderError)
    }

    private var wordText: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(word.polish)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.appInk)
            Text(word.russian)
                .font(.subheadline)
                .foregroundStyle(Color.subtleText)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var wordActions: some View {
        HStack(spacing: 8) {
            CategoryMenu(selection: Binding(
                get: { word.category },
                set: { word.category = $0 }
            )) {
                HStack(spacing: 5) {
                    Text(word.category.rawValue)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .fixedSize()
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.appAccent)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Категория слова \(word.polish): \(word.category.rawValue)")
            .accessibilityHint("Выбрать другую категорию")
            if !folderLibrary.options.isEmpty {
                Menu {
                    ForEach(folderLibrary.options) { folder in
                        let included = word.folderIDs.contains(folder.id)
                        Button {
                            do {
                                try FolderStore.setMembership(wordID: word.persistentModelID, folderID: folder.id,
                                                              included: !included, container: modelContext.container)
                            } catch { folderError = error.localizedDescription }
                        } label: {
                            Label(folder.name, systemImage: included ? "checkmark" : "folder")
                        }
                    }
                } label: {
                    Image(systemName: word.folderIDs.isEmpty ? "folder.badge.plus" : "folder.fill")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("Папки слова \(word.polish)")
            }
            PronounceButton(text: word.polish, language: .polish)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

#Preview {
    WordListView()
        .modelContainer(for: [Word.self, WordFolder.self], inMemory: true)
        .environment(FolderLibraryStore())
}
