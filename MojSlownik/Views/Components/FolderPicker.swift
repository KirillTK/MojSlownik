import SwiftUI
import SwiftData

struct FolderPicker: View {
    @Binding var selectedFolderID: UUID?
    var allowsAll = false
    var compact = false
    /// Grows with Dynamic Type so the title is not truncated at accessibility sizes.
    @ScaledMetric(relativeTo: .subheadline) private var compactMaxWidth: CGFloat = 220

    @Environment(\.modelContext) private var modelContext
    @Environment(FolderLibraryStore.self) private var library
    @State private var showFolders = false
    @State private var showCreateFolder = false
    @State private var folderName = ""
    @State private var creationError: String?
    @State private var isEditingFolders = false
    @State private var folderToRename: FolderLibraryStore.Option?
    @State private var renameName = ""
    @State private var renameError: String?
    @State private var pendingDeletion: FolderLibraryStore.Option?
    @State private var deletionError: String?
    @State private var managementError: String?

    private var emptyTitle: String { allowsAll ? "Все папки" : "Без папки" }

    private var selectionTitle: String {
        library.options.first { $0.id == selectedFolderID }?.name ?? emptyTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                refresh()
                showFolders = true
            } label: {
                pickerLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Папка: \(selectionTitle)")
            .accessibilityHint("Выбрать или создать папку")
            if let creationError, !showFolders {
                errorLabel(creationError)
            }
        }
        .sheet(isPresented: $showFolders) { folderSheet }
        .onAppear { refresh() }
        .onChange(of: library.options.map(\.id)) { reconcileSelection() }
        .onChange(of: showFolders) {
            if !showFolders { resetFolderManagementState() }
        }
    }

    @ViewBuilder
    private var pickerLabel: some View {
        let content = HStack(spacing: compact ? AppSpacing.xs : 10) {
            if compact {
                Image(systemName: "folder").fontWeight(.medium)
            } else {
                Image(systemName: "folder").fontWeight(.medium).foregroundStyle(Color.appInk)
            }
            VStack(alignment: .leading, spacing: 2) {
                if !compact {
                    Text("Папка")
                        .font(.caption)
                        .foregroundStyle(Color.subtleText)
                }
                Text(selectionTitle)
                    .font(compact ? nil : .subheadline.weight(.medium))
                    .multilineTextAlignment(.leading)
                    .lineLimit(compact ? 1 : nil)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: !compact)
            }
            if !compact { Spacer(minLength: 8) }
            if compact {
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            } else {
                Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(Color.subtleText)
            }
        }
        if compact {
            content
                .frame(maxWidth: compactMaxWidth, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
                .chipStyle(isSelected: selectedFolderID != nil)
        } else {
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .cardStyle(cornerRadius: AppRadius.control)
        }
    }

    private var folderSheet: some View {
        NavigationStack {
            List {
                Section {
                    if !isEditingFolders {
                        optionRow(id: nil, name: emptyTitle)
                    }
                    ForEach(library.options) { option in
                        if isEditingFolders {
                            managementRow(option)
                        } else {
                            optionRow(id: option.id, name: option.name)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        pendingDeletion = option
                                    } label: {
                                        Label("Удалить", systemImage: "trash")
                                    }
                                    .tint(.red)
                                }
                        }
                    }
                    .onMove(perform: moveFolders)
                }
                if !isEditingFolders {
                    Section {
                        Button {
                            folderName = ""
                            creationError = nil
                            showCreateFolder = true
                        } label: {
                            Label("Создать папку", systemImage: "folder.badge.plus")
                                .frame(minHeight: 44)
                        }
                    }
                }
                if let creationError {
                    Section { errorLabel(creationError) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Выберите папку")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEditingFolders ? "Готово" : "Закрыть") {
                        if isEditingFolders {
                            isEditingFolders = false
                        } else {
                            showFolders = false
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !isEditingFolders {
                        Button("Править") { isEditingFolders = true }
                            .disabled(library.options.isEmpty)
                    }
                }
            }
            .confirmationDialog(
                "Удалить папку «\(pendingDeletion?.name ?? "")»? Слова останутся в словаре.",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { folder in
                Button("Удалить папку", role: .destructive) { deleteFolder(folder) }
                Button("Отмена", role: .cancel) { pendingDeletion = nil }
            }
            .errorAlert(title: "Не удалось изменить папки", error: $managementError)
            .errorAlert(title: "Не удалось удалить папку", error: $deletionError)
            .navigationDestination(isPresented: $showCreateFolder) {
                Form {
                    Section("Название папки") {
                        TextField("Например, Урок 1", text: $folderName)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.done)
                            .onSubmit { if !folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { createFolder() } }
                    }
                    if let creationError {
                        Section { errorLabel(creationError) }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.appBackground)
                .navigationTitle("Новая папка")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Создать") { createFolder() }
                            .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationDestination(item: $folderToRename) { folder in
                Form {
                    Section("Название папки") {
                        TextField("Например, Урок 1", text: $renameName)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.done)
                            .onSubmit {
                                if !renameName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    renameFolder(folder)
                                }
                            }
                    }
                    if let renameError {
                        Section { errorLabel(renameError) }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.appBackground)
                .navigationTitle("Переименовать папку")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Сохранить") { renameFolder(folder) }
                            .disabled(renameName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .environment(\.editMode, .constant(isEditingFolders ? .active : .inactive))
        .tint(Color.appAccentText)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func optionRow(id: UUID?, name: String) -> some View {
        Button {
            selectedFolderID = id
            showFolders = false
        } label: {
            HStack {
                Text(name).foregroundStyle(Color.appInk)
                Spacer()
                if selectedFolderID == id {
                    Image(systemName: "checkmark")
                        .fontWeight(.medium)
                        .foregroundStyle(Color.appAccentStrong)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(selectedFolderID == id ? .isSelected : [])
    }

    private func managementRow(_ option: FolderLibraryStore.Option) -> some View {
        HStack(spacing: 12) {
            Text(option.name)
                .foregroundStyle(Color.appInk)
            Spacer()
            Button {
                renameName = option.name
                renameError = nil
                folderToRename = option
            } label: {
                Image(systemName: "pencil")
                    .fontWeight(.medium)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Переименовать папку «\(option.name)»")
            Button(role: .destructive) {
                pendingDeletion = option
            } label: {
                Image(systemName: "trash")
                    .fontWeight(.medium)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Удалить папку «\(option.name)»")
        }
        .frame(minHeight: 44)
    }

    private func errorLabel(_ error: String) -> some View {
        Label(error, systemImage: "exclamationmark.circle")
            .font(.caption)
            .foregroundStyle(Color.appError)
    }

    private func refresh() {
        do {
            try library.load(context: modelContext)
            reconcileSelection()
            creationError = nil
        } catch { creationError = error.localizedDescription }
    }

    private func reconcileSelection() {
        if let selectedFolderID, !library.options.contains(where: { $0.id == selectedFolderID }) {
            self.selectedFolderID = nil
        }
    }

    private func deleteFolder(_ folder: FolderLibraryStore.Option) {
        pendingDeletion = nil
        do {
            try library.delete(id: folder.id, context: modelContext)
            reconcileSelection()
        } catch { deletionError = error.localizedDescription }
    }

    private func createFolder() {
        do {
            selectedFolderID = try library.create(name: folderName, context: modelContext)
            creationError = nil
            showCreateFolder = false
            showFolders = false
        } catch { creationError = error.localizedDescription }
    }

    private func moveFolders(from source: IndexSet, to destination: Int) {
        var ids = library.options.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        do {
            try library.reorder(ids: ids, context: modelContext)
        } catch { managementError = error.localizedDescription }
    }

    private func renameFolder(_ folder: FolderLibraryStore.Option) {
        do {
            try library.rename(id: folder.id, name: renameName, context: modelContext)
            renameError = nil
            folderToRename = nil
        } catch { renameError = error.localizedDescription }
    }

    private func resetFolderManagementState() {
        isEditingFolders = false
        folderToRename = nil
        renameName = ""
        renameError = nil
        pendingDeletion = nil
        managementError = nil
    }
}
