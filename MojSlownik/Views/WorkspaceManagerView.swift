import SwiftUI
import SwiftData

/// “Languages” sheet: switch, reorder and delete workspaces, add a pair. Deleting is a soft delete:
/// words and folders are hidden with the workspace and return when the pair is added again.
struct WorkspaceManagerView: View {
    @Environment(WorkspaceStore.self) private var workspaces
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var storedWords: [Word]
    @Query private var storedFolders: [WordFolder]
    @State private var editMode: EditMode = .inactive
    @State private var pendingDelete: WorkspaceStore.Option?
    @State private var showWizard = false
    @State private var errorMessage: String?

    private var isEditing: Bool { editMode == .active }
    private var isOnlyActive: Bool { workspaces.options.count <= 1 }

    var body: some View {
        NavigationStack {
            let counts = WorkspaceScope.wordCounts(storedWords)
            List {
                Section {
                    ForEach(workspaces.options) { option in
                        row(option, wordCount: counts[option.id] ?? 0)
                            .deleteDisabled(isOnlyActive)
                    }
                    .onDelete { offsets in
                        guard !isOnlyActive, let index = offsets.first else { return }
                        pendingDelete = workspaces.options[index]
                    }
                    .onMove(perform: move)
                }
                Section {
                    Button { showWizard = true } label: {
                        Label("Add language", systemImage: "plus")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .tint(Color.appAccentText)
                    .listRowBackground(Color.cardBackground)
                    .accessibilityIdentifier("addWorkspaceButton")
                } footer: {
                    infoLine("A deleted language is hidden together with its words and folders. Add the same pair again and everything comes back.")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .environment(\.editMode, $editMode)
            .navigationTitle("Languages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        editMode = isEditing ? .inactive : .active
                    } label: {
                        Text(isEditing ? "Done" : "Edit")
                            .fontWeight(isEditing ? .bold : .regular)
                    }
                    .tint(Color.appAccentText)
                    .accessibilityIdentifier("editWorkspacesButton")
                }
                if !isEditing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .tint(Color.appAccentText)
                            .accessibilityIdentifier("manageWorkspacesDone")
                    }
                }
            }
            .confirmationDialog(
                "Delete “\(pendingDelete.map(WorkspaceLabels.name(of:)) ?? "")”?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible, presenting: pendingDelete
            ) { option in
                Button("Delete", role: .destructive) { delete(option) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Words and folders will be hidden. Add this pair again and everything comes back.")
            }
            .sheet(isPresented: $showWizard) { WorkspaceWizardView(presentation: .sheet) }
            .errorAlert(title: "Couldn’t change languages", error: $errorMessage)
        }
        .tint(.appAccentText)
    }

    private func row(_ option: WorkspaceStore.Option, wordCount: Int) -> some View {
        let isActive = option.id == workspaces.activeID
        let folders = WorkspaceScope.folders(storedFolders, workspaceID: option.id).count
        return Button {
            workspaces.select(id: option.id)
        } label: {
            HStack(spacing: AppSpacing.s) {
                Text(option.pair.term.flag)
                    .font(.title2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(WorkspaceLabels.name(of: option))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.appInk)
                    Text(verbatim: "\(WorkspaceLabels.wordCount(wordCount)) · \(WorkspaceLabels.folderCount(folders))")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Color.subtleText)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: AppSpacing.xs)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Color.appAccentStrong)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.cardBackground)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityIdentifier("workspaceRow-\(option.termCode)-\(option.translationCode)")
    }

    private func infoLine(_ text: LocalizedStringKey) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.xxs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: AppSpacing.xs))
        return layout {
            Image(systemName: "info.circle")
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .foregroundStyle(Color.subtleText)
        .textCase(nil)
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ids = workspaces.options.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        do { try workspaces.reorder(ids: ids) } catch { errorMessage = error.localizedDescription }
    }

    private func delete(_ option: WorkspaceStore.Option) {
        do { try workspaces.delete(id: option.id) } catch { errorMessage = error.localizedDescription }
        pendingDelete = nil
    }
}
