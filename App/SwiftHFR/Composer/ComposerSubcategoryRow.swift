import SwiftUI

// Port of HFRswift/Swift/AnswerView.swift (sub-category `Picker`, :395-420) @ 2440d79 (GAP-098). Moved out of
// `ReplyComposerView` unchanged (#653).
/// The form's sub-categories of a new topic (LOT-089) as a menu (legacy `Picker`, `AnswerView.swift:411`); a failed read says so
/// and offers a retry.
struct ComposerSubcategoryRow: View {
    let model: ReplyComposerModel

    /// The row has something to show: loading, the options or a failed read (a form without the select shows nothing).
    static func shows(_ picker: NewTopicSubcategories) -> Bool {
        picker.isLoading || !picker.options.isEmpty || picker.warning != nil
    }

    var body: some View {
        if model.picker.isLoading {
            HStack {
                Text("Sous-catégorie")
                Spacer()
                ProgressView().accessibilityLabel("Chargement des sous-catégories")
            }
            .padding(.vertical, 10)
        } else if !model.picker.options.isEmpty {
            Picker("Sous-catégorie", selection: Binding(
                get: { model.picker.selected ?? "" }, set: { model.select(subcategory: $0) }
            )) {
                ForEach(model.picker.options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.menu)
            .disabled(!model.canEdit)
            .padding(.vertical, 2)
        } else if let warning = model.picker.warning {
            VStack(alignment: .leading, spacing: 6) {
                Text(warning).scaledFont(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Réessayer") { Task { await model.retrySubcategories() } }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
