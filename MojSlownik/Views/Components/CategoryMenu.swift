import SwiftUI

struct CategoryMenu<Label: View>: View {
    @Binding var selection: WordCategory
    private let label: Label

    init(selection: Binding<WordCategory>, @ViewBuilder label: () -> Label) {
        _selection = selection
        self.label = label()
    }

    var body: some View {
        Menu {
            Picker("Category", selection: $selection) {
                ForEach(WordCategory.allCases) { category in
                    Text(category.title).tag(category)
                }
            }
        } label: {
            label
        }
    }
}
