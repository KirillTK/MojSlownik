import SwiftUI
import SwiftData

struct WordListView: View {
    @Query(sort: \Word.createdAt, order: .reverse) private var storedWords: [Word]
    private var words: [Word] { storedWords.filter(\.isActive) }

    @Environment(FolderLibraryStore.self) private var folderLibrary
    @Environment(VocabularyStore.self) private var vocabulary
    @State private var selectedFolderID: UUID?
    @State private var showDeleteFolder = false
    @State private var deletionError: String?
    @State private var folderError: String?
    @State private var selectedCategory: WordCategory?
    @State private var searchText = ""
    @State private var showAddSheet = false
    @State private var showAccount = false
    @State private var showScanner = false
    @State private var scannedResult: ScannedText?
    @State private var didHandleTestPrefill = false
    @ScaledMetric(relativeTo: .title2) private var fabScaled: CGFloat = 56

    private var fabSize: CGFloat { min(fabScaled, 72) }

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
                        EmptyStateView(icon: "character.book.closed", title: "Словарь пуст",
                                       message: "Добавьте первое слово кнопкой «плюс» или отсканируйте его камерой.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.bottom, fabSize)
                    } else {
                        List {
                            if filteredWords.isEmpty {
                                EmptyStateView(icon: "magnifyingglass", title: "Нет подходящих слов",
                                               message: "Проверьте выбранную папку, категорию и поисковый запрос.") {
                                    Button("Показать все слова") {
                                        selectedFolderID = nil
                                        selectedCategory = nil
                                        searchText = ""
                                    }
                                    .font(.body.weight(.bold))
                                    .frame(minHeight: 44)
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                            ForEach(filteredWords) { word in
                                WordRow(word: word)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: AppSpacing.xs, leading: AppSpacing.l, bottom: AppSpacing.xs, trailing: AppSpacing.l))
                                    .listRowSeparatorTint(Color.appBorder)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            deleteWord(word)
                                        } label: {
                                            Label("Удалить", systemImage: "trash")
                                        }
                                        .tint(.red)
                                    }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .contentMargins(.bottom, fabSize + AppSpacing.m + AppSpacing.m, for: .scrollContent)
                        .searchable(text: $searchText, prompt: "Найти слово")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.appBackground)
            .foregroundStyle(Color.appInk)
            .overlay(alignment: .bottomTrailing) { floatingActions }
            .navigationTitle("Словарь")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if selectedFolderID != nil {
                        Button("Удалить папку", systemImage: "folder.badge.minus") { showDeleteFolder = true }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Аккаунт", systemImage: "person.crop.circle") { showAccount = true }
                        .tint(Color.appAccentText)
                        .accessibilityIdentifier("accountButton")
                }
            }
            .sheet(isPresented: $showAccount) {
                AccountView()
            }
            .sensoryFeedback(.selection, trigger: selectedCategory)
            .sensoryFeedback(trigger: words.count) { old, new in
                new > old ? .impact(weight: .light) : nil
            }
            .confirmationDialog("Удалить папку «\(folderLibrary.options.first { $0.id == selectedFolderID }?.name ?? "")»? Слова останутся в словаре.", isPresented: $showDeleteFolder, titleVisibility: .visible) {
                Button("Удалить папку", role: .destructive) {
                    guard let id = selectedFolderID else { return }
                    do {
                        try folderLibrary.delete(id: id)
                        selectedFolderID = nil
                    } catch { folderError = error.localizedDescription }
                }
            }
            .errorAlert(title: "Не удалось изменить папку", error: $folderError)
            .errorAlert(title: "Не удалось удалить слово", error: $deletionError)
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
                #if DEBUG
                if !didHandleTestPrefill,
                   let prefill = UITestLaunchConfiguration.current?.prefill {
                    didHandleTestPrefill = true
                    scannedResult = ScannedText(text: prefill)
                }
                #endif
            }
        }
        .tint(.appAccentText)
    }

    private var floatingActions: some View {
        HStack(spacing: AppSpacing.s) {
            Button {
                showScanner = true
            } label: {
                Image(systemName: "text.viewfinder")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.appInk)
                    .frame(width: fabSize - 4, height: fabSize - 4)
                    .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Сканировать текст")
            .accessibilityIdentifier("scanButton")
            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.appOnAccent)
                    .frame(width: fabSize, height: fabSize)
                    .background(Color.appAccent, in: RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Добавить слово")
            .accessibilityIdentifier("addWordButton")
        }
        .padding(.trailing, AppSpacing.l)
        .padding(.bottom, AppSpacing.m)
        .ignoresSafeArea(.keyboard)
    }

    private var categoryFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.xs) {
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
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xs)
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
                Text(count.formatted())
                    .monospacedDigit()
            }
            .chipStyle(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), слов: \(count)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func deleteWord(_ word: Word) {
        do {
            try vocabulary.deleteWord(word)
        } catch { deletionError = error.localizedDescription }
    }
}

struct ScannedText: Identifiable {
    let id = UUID()
    let text: String
}

/// Empty/no-result state: soft-yellow icon tile, title, explanation and an optional text action.
private struct EmptyStateView<Actions: View>: View {
    let icon: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions
    @ScaledMetric(relativeTo: .title) private var tile: CGFloat = 64

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            Image(systemName: icon)
                .font(.title)
                .fontWeight(.medium)
                .foregroundStyle(Color.appInk)
                .frame(width: tile, height: tile)
                .background(Color.appAccentSoft, in: RoundedRectangle(cornerRadius: AppRadius.hero - 4, style: .continuous))
                .padding(.bottom, AppSpacing.xxs)
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.appInk)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.subtleText)
            actions
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.xxl)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(icon: String, title: String, message: String) {
        self.init(icon: icon, title: title, message: message) { EmptyView() }
    }
}

private struct WordRow: View {
    let word: Word
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(FolderLibraryStore.self) private var folderLibrary
    @Environment(VocabularyStore.self) private var vocabulary
    @State private var folderError: String?
    @State private var categoryError: String?

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    wordText
                    translation
                    HStack(spacing: AppSpacing.xs) {
                        ring
                        PronounceButton(text: word.polish, language: .polish)
                    }
                    HStack(spacing: AppSpacing.xs) {
                        categoryMenu
                        folderMenu
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    HStack(alignment: .center, spacing: AppSpacing.s) {
                        wordText
                        Spacer(minLength: 0)
                        ring
                        PronounceButton(text: word.polish, language: .polish)
                    }
                    HStack(spacing: AppSpacing.xs) {
                        translation
                        Spacer(minLength: 0)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: AppSpacing.xs) { categoryMenu; folderMenu }
                            VStack(alignment: .trailing, spacing: 0) { categoryMenu; folderMenu }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .errorAlert(title: "Не удалось изменить папку", error: $folderError)
        .errorAlert(title: "Не удалось изменить категорию", error: $categoryError)
    }

    private var wordText: some View {
        Text(word.polish)
            .font(.title3.weight(.bold))
            .foregroundStyle(Color.appInk)
            .frame(minWidth: 160, alignment: .leading)
            .layoutPriority(1)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var translation: some View {
        Text(word.russian)
            .font(.subheadline)
            .foregroundStyle(Color.subtleText)
            .layoutPriority(1)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var ring: some View {
        KnowledgeTierBadge(word: word, level: KnowledgeProgressService.tier(for: word))
    }

    private var categoryMenu: some View {
        CategoryMenu(selection: Binding(
            get: { word.category },
            set: { newCategory in
                do { try vocabulary.setCategory(newCategory, for: word) }
                catch { categoryError = error.localizedDescription }
            }
        )) {
            HStack(spacing: AppSpacing.xxs) {
                Image(systemName: "tag")
                    .font(.caption2)
                    .fixedSize()
                Text(word.category.rawValue)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .fixedSize()
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.subtleText)
            .padding(.horizontal, AppSpacing.xs)
            .frame(minHeight: 28)
            .background(Color.appSecondarySurface, in: Capsule())
            .frame(maxWidth: 120, minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Категория слова \(word.polish): \(word.category.rawValue)")
        .accessibilityHint("Выбрать другую категорию")
    }

    @ViewBuilder
    private var folderMenu: some View {
        if !folderLibrary.options.isEmpty {
            Menu {
                if !word.folderIDs.isEmpty {
                    Button(role: .destructive) {
                        do {
                            try vocabulary.removeFromAllFolders(word)
                        } catch { folderError = error.localizedDescription }
                    } label: {
                        Label("Убрать из всех папок", systemImage: "folder.badge.minus")
                    }
                }
                ForEach(folderLibrary.options) { folder in
                    let included = word.folderIDs.contains(folder.id)
                    Button {
                        do {
                            try vocabulary.setMembership(of: word, folderID: folder.id, included: !included)
                        } catch { folderError = error.localizedDescription }
                    } label: {
                        Label(folder.name, systemImage: included ? "checkmark" : "folder")
                    }
                }
            } label: {
                Image(systemName: word.folderIDs.isEmpty ? "folder.badge.plus" : "folder")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.appInk)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("Папки слова \(word.polish)")
        }
    }
}

#Preview {
    let resources = AppResources.preview
    WordListView()
        .modelContainer(resources.container)
        .environment(resources.folders)
        .environment(resources.vocabulary)
        .environment(resources.dailyStudy)
        .environment(resources.achievements)
        .environment(resources.auth)
}
