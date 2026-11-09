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
            Picker("Категория", selection: $selection) {
                ForEach(WordCategory.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }
        } label: {
            label
        }
    }
}
