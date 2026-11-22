import SwiftUI

/// Large title with the workspace menu («🇵🇱 Польский» plus the system chevron): switches the active
/// workspace, adds a language and opens the «Языки» sheet. Owns the wizard and manager presentation.
private struct WorkspaceTitleMenu: ViewModifier {
    /// All stored words; counts are grouped by workspace here.
    let words: [Word]

    @Environment(WorkspaceStore.self) private var workspaces
    @State private var showNewLanguage = false
    @State private var showManager = false

    private var title: String {
        workspaces.active.map { WorkspaceLabels.title(of: $0, among: workspaces.options) } ?? "Словарь"
    }

    func body(content: Content) -> some View {
        let counts = WorkspaceScope.wordCounts(words)
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)  // O1: the large-title menu shows no chevron on iOS 26
            .toolbarTitleMenu {
                Picker("Язык", selection: Binding(
                    get: { workspaces.activeID ?? UUID() },
                    set: { workspaces.select(id: $0) }
                )) {
                    ForEach(workspaces.options) { option in
                        // A second Text inside a picker option becomes a second row, so the count shares one Text.
                        Text("\(WorkspaceLabels.menuLabel(of: option))\n\(RussianPlural.words(counts[option.id] ?? 0))")
                            .tag(option.id)
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Button("Новый язык…", systemImage: "plus") { showNewLanguage = true }
                Button("Управлять языками", systemImage: "gearshape") { showManager = true }
            }
            .sheet(isPresented: $showNewLanguage) {
                WorkspaceWizardView(presentation: .sheet)
            }
            .sheet(isPresented: $showManager) {
                WorkspaceManagerView()
            }
    }
}

extension View {
    /// Replaces the fixed navigation title with the workspace title and its switching menu.
    func workspaceTitleMenu(words: [Word]) -> some View {
        modifier(WorkspaceTitleMenu(words: words))
    }
}
