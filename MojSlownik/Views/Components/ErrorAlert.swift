import SwiftUI

extension View {
    func errorAlert(title: LocalizedStringKey, error: Binding<String?>) -> some View {
        alert(title, isPresented: Binding(
            get: { error.wrappedValue != nil },
            set: { if !$0 { error.wrappedValue = nil } }
        )) {
            Button("OK") { error.wrappedValue = nil }
        } message: {
            Text(error.wrappedValue ?? "")
        }
    }
}
