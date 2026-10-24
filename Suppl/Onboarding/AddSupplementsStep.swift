import SwiftUI
import SwiftData

struct AddSupplementsStep: View {
    let next: () -> Void
    @Query(sort: \Supplement.createdAt) private var supplements: [Supplement]
    @State private var searching = false

    var body: some View {
        Group {
            if supplements.isEmpty {
                OnboardingPage("What do you take?", subtitle: "Search or type it in. You can always add more later.",
                               primary: "Add a supplement", secondary: "Do this later",
                               onPrimary: { searching = true }, onSecondary: next) {
                    EmptyView()
                }
            } else {
                OnboardingPage("What do you take?", subtitle: "Add everything you take regularly.",
                               onPrimary: next) {
                    list
                    Button { searching = true } label: {
                        Label("Add another", systemImage: "plus")
                            .font(.headline)
                            .frame(minHeight: 44)
                    }
                }
            }
        }
        .sheet(isPresented: $searching) { SupplementSearchView() }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(supplements) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.body.weight(.semibold))
                    Text("\(item.doseText) · \(item.timingNote)")
                        .font(.subheadline)
                        .foregroundStyle(Color.forest.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
                if item.id != supplements.last?.id { Divider() }
            }
        }
        .card()
    }
}

#if DEBUG
#Preview {
    AddSupplementsStep {}
        .padding(24)
        .background(Color.cream)
        .foregroundStyle(Color.forest)
        .modelContainer(PreviewData.container())
}
#endif
