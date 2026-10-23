import SwiftUI
import SwiftData
import SupplCore

/// Search the bundled catalog, or add something by hand. Either way the form opens fully editable.
struct SupplementSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var draft: SupplementDraft?
    @State private var saved = false

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    private var results: [CatalogEntry] {
        trimmed.isEmpty ? Content.allEntries : Content.search(trimmed)
    }

    var body: some View {
        NavigationStack {
            List {
                manualSection
                resultsSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.cream)
            .foregroundStyle(Color.forest)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search supplements")
            .autocorrectionDisabled()
            .navigationTitle("Add supplement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(item: $draft, onDismiss: { if saved { dismiss() } }) { draft in
                SupplementForm(supplement: nil, draft: draft, onSaved: { saved = true })
            }
        }
    }

    private var manualSection: some View {
        Section {
            Button {
                draft = SupplementDraft(name: trimmed)
            } label: {
                Label(trimmed.isEmpty ? "Add manually" : "Add \"\(trimmed)\" manually", systemImage: "square.and.pencil")
                    .frame(minHeight: 44)
            }
        } footer: {
            Text("We don't know your exact product. Check your label.")
        }
    }

    @ViewBuilder private var resultsSection: some View {
        if !results.isEmpty {
            Section(trimmed.isEmpty ? "Common supplements" : "Results") {
                ForEach(results) { entry in
                    Button {
                        draft = SupplementDraft(entry)
                    } label: {
                        row(entry)
                    }
                }
            }
        } else if !trimmed.isEmpty {
            Section {
                Text("No matches. You can add it manually above.")
                    .foregroundStyle(Color.forest.opacity(0.8))
            }
        }
    }

    private func row(_ entry: CatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.name)
                .font(.body.weight(.semibold))
            Text(entry.category.capitalized)
                .font(.subheadline)
                .foregroundStyle(Color.forest.opacity(0.8))
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

#if DEBUG
#Preview {
    SupplementSearchView()
        .modelContainer(PreviewData.container(empty: true))
}
#endif
