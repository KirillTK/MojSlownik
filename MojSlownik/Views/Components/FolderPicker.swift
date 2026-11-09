import SwiftUI
import SwiftData

struct FolderPicker: View {
    @Binding var selectedFolderID: UUID?
    var allowsAll = false

    @Environment(\.modelContext) private var modelContext
    @Environment(FolderLibraryStore.self) private var library
    @State private var showFolders = false
    @State private var showCreateFolder = false
    @State private var folderName = ""
    @State private var creationError: String?

    private var emptyTitle: String { allowsAll ? "Все слова" : "Без папки" }

    private var selectionTitle: String {
        library.options.first { $0.id == selectedFolderID }?.name ?? emptyTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                refresh()
                showFolders = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "folder")
                        .foregroundStyle(Color.appAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Папка")
                            .font(.caption)
                            .foregroundStyle(Color.subtleText)
                        Text(selectionTitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.appInk)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appAccent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .cardStyle(cornerRadius: 14)
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
    }

    private var folderSheet: some View {
        NavigationStack {
            List {
                Section {
                    optionRow(id: nil, name: emptyTitle)
                    ForEach(library.options) { option in
                        optionRow(id: option.id, name: option.name)
                    }
                }
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
                    Button("Готово") { showFolders = false }
                }
            }
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
                .navigationTitle("Новая папка")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Создать") { createFolder() }
                            .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .tint(Color.appAccent)
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
                    Image(systemName: "checkmark").foregroundStyle(Color.appAccent)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(selectedFolderID == id ? .isSelected : [])
    }

    private func errorLabel(_ error: String) -> some View {
        Label(error, systemImage: "exclamationmark.circle")
            .font(.caption)
            .foregroundStyle(.red)
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

    private func createFolder() {
        do {
            selectedFolderID = try library.create(name: folderName, context: modelContext)
            creationError = nil
            showCreateFolder = false
            showFolders = false
        } catch { creationError = error.localizedDescription }
    }
}
