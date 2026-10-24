import SwiftUI
import SwiftData
import SupplCore

/// Everything we know about one supplement. All of it is free, including the safety notes.
struct SupplementDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var all: [Supplement]

    let supplement: Supplement

    @State private var editing = false
    @State private var confirmingRemove = false

    var body: some View {
        // After Remove the model is gone before the pop finishes; don't read it.
        if supplement.isDeleted || supplement.modelContext == nil {
            Color.cream.ignoresSafeArea()
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                planCard
                if let entry {
                    aboutCard(entry)
                } else {
                    noInfoCard
                }
                if !ruleNotes.isEmpty {
                    rulesCard
                }
                removeButton
            }
            .padding(20)
        }
        .background(Color.cream.ignoresSafeArea())
        .foregroundStyle(Color.forest)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            SupplementForm(supplement: supplement, allowsRemove: false)
        }
        .confirmationDialog("Remove \(supplement.name)?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive, action: remove)
        } message: {
            Text("Its reminders stop too.")
        }
    }

    private var entry: CatalogEntry? { Content.entry(id: supplement.catalogID) }

    private var ruleNotes: [InteractionRule] {
        RuleEvaluator.notes(for: supplement.dosePlan, allPlans: all.map(\.dosePlan), rules: RuleBook.all)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(supplement.name)
                .font(.largeTitle.bold())
            if !supplement.brand.isEmpty {
                Text(supplement.brand)
                    .font(.title3)
                    .foregroundStyle(Color.forest.opacity(0.8))
            }
        }
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            fact("Dose", supplement.doseText)
            fact("How often", supplement.frequencyText)
            fact("When", whenText)
            fact("With food", supplement.withFood ? "Yes" : "No")
            if supplement.clinicianDirected {
                Label("A clinician told you to take this. We won't move its reminders.", systemImage: "stethoscope")
                    .font(.subheadline)
            }
            if !supplement.notes.isEmpty {
                fact("Notes", supplement.notes)
            }
        }
        .card()
    }

    private var whenText: String {
        let time = timeText(supplement.slot.minutes)
        if supplement.clinicianDirected { return "At your saved time, \(time). Context won't move this reminder." }
        if supplement.slot == .postWorkout {
            return Features.current.smartTiming
                ? "Usually around \(time). When workout data is available, this can move after a workout."
                : "Usually around \(time). With Pro and workout data available, this can move after a workout."
        }
        return "\(supplement.timingNote), usually \(time)"
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.forest.opacity(0.8))
            Text(value)
                .font(.body)
        }
        .accessibilityElement(children: .combine)
    }

    private func aboutCard(_ entry: CatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About \(entry.name.lowercased())")
                .font(.headline)
            Text(entry.note)
            Text("General information. Check it against your label.")
                .font(.footnote)
                .foregroundStyle(Color.forest.opacity(0.8))
            sourceLinks(entry)
        }
        .card()
    }

    private func sourceLinks(_ entry: CatalogEntry) -> some View {
        let urls = entry.sources.compactMap { URL(string: $0) }
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(urls, id: \.self) { url in
                Link(destination: url) {
                    Label("Source: \(url.host() ?? url.absoluteString)", systemImage: "link")
                        .frame(minHeight: 44)
                }
            }
            if let examine = entry.examineURL.flatMap({ URL(string: $0) }) {
                Link(destination: examine) {
                    Label("Read more on Examine", systemImage: "arrow.up.right.square")
                        .frame(minHeight: 44)
                }
            }
        }
        .font(.subheadline)
    }

    private var noInfoCard: some View {
        Text("We don't have general information for this one. Your label and your pharmacist are the best guide.")
            .font(.callout)
            .card()
    }

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Good to know")
                .font(.headline)
            ForEach(ruleNotes) { rule in
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.explanation)
                    ForEach(rule.sources.compactMap { URL(string: $0) }, id: \.self) { url in
                        Link("Source: \(url.host() ?? url.absoluteString)", destination: url)
                            .font(.subheadline)
                            .frame(minHeight: 44)
                    }
                }
            }
            Text("General information, not medical advice. Ask a pharmacist about your own situation.")
                .font(.footnote)
                .foregroundStyle(Color.forest.opacity(0.8))
        }
        .card()
    }

    private var removeButton: some View {
        Button(role: .destructive) {
            confirmingRemove = true
        } label: {
            Text("Remove supplement")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.top, 8)
    }

    private func remove() {
        context.delete(supplement)
        try? context.save()
        Reminders.reschedule()
        dismiss()
    }
}

#if DEBUG
#Preview {
    let container = PreviewData.container()
    let first = (try? container.mainContext.fetch(FetchDescriptor<Supplement>()))?.first
    return NavigationStack {
        if let first {
            SupplementDetailView(supplement: first)
        }
    }
    .modelContainer(container)
}
#endif
