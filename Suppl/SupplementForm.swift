import SwiftUI
import SwiftData
import SupplCore

struct SupplementForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let supplement: Supplement?
    /// Prefill from search. Ignored when editing.
    var draft: SupplementDraft? = nil
    /// The detail screen has its own Remove, so it hides this one.
    var allowsRemove = true
    var onSaved: (() -> Void)? = nil

    @State private var name = ""
    @State private var brand = ""
    @State private var dose = 1.0
    @State private var unit = "capsule"
    @State private var slot = Slot.breakfast
    @State private var withFood = true
    @State private var specificDays = false
    @State private var weekdays: Set<Int> = []
    @State private var clinicianDirected = false
    @State private var notes = ""
    @State private var catalogID: String?
    /// The name the catalog id was chosen for. If the user renames it, we look the id up again.
    @State private var catalogName = ""
    @State private var confirmingDelete = false

    private static let common = ["Vitamin D", "Magnesium", "Omega-3", "Multivitamin", "Creatine",
                                 "Iron", "Vitamin B12", "Zinc", "Probiotic", "Vitamin C"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Brand (optional)", text: $brand)
                } footer: {
                    if supplement == nil && name.isEmpty {
                        suggestions
                    }
                }

                Section("Dose") {
                    HStack {
                        TextField("Amount", value: $dose, format: .number)
                            .keyboardType(.decimalPad)
                        Picker("Unit", selection: $unit) {
                            ForEach(Supplement.units, id: \.self) { Text($0) }
                        }
                        .labelsHidden()
                    }
                }

                Section("When") {
                    Picker("Moment", selection: $slot) {
                        ForEach(Slot.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    Toggle("Take with food", isOn: $withFood)
                }

                frequencySection

                Section {
                    Toggle("A clinician told me to take this", isOn: $clinicianDirected)
                } footer: {
                    Text("We'll keep these reminders at the time you set and never move them around your day.")
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                if supplement != nil && allowsRemove {
                    Section {
                        Button("Remove supplement", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.cream)
            .navigationTitle(supplement == nil ? "Add supplement" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .confirmationDialog("Remove \(name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Remove", role: .destructive, action: delete)
            }
            .onAppear(perform: load)
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && dose > 0 && !(specificDays && weekdays.isEmpty)
    }

    private var frequencySection: some View {
        Section {
            Picker("How often", selection: $specificDays) {
                Text("Every day").tag(false)
                Text("Specific days").tag(true)
            }
            .pickerStyle(.segmented)
            if specificDays {
                weekdayChips
            }
        } header: {
            Text("How often")
        } footer: {
            if specificDays && weekdays.isEmpty {
                Text("Pick at least one day.")
            }
        }
    }

    private var weekdayChips: some View {
        let calendar = Calendar.current
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], spacing: 6) {
            ForEach(Weekdays.ordered(calendar), id: \.self) { day in
                weekdayChip(day, short: calendar.veryShortWeekdaySymbols[day - 1],
                            full: calendar.weekdaySymbols[day - 1])
            }
        }
    }

    private func weekdayChip(_ day: Int, short: String, full: String) -> some View {
        let on = weekdays.contains(day)
        return Button {
            if on { weekdays.remove(day) } else { weekdays.insert(day) }
        } label: {
            Text(short)
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
                .background(on ? Color.forest : Color.softSage)
                .foregroundStyle(on ? Color.cream : Color.forest)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        // Borderless so each chip is its own tap target inside the Form row.
        .buttonStyle(.borderless)
        .accessibilityLabel(full)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var suggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(Self.common, id: \.self) { item in
                    Button(item) { name = item }
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(Color.sage.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding(.top, 8)
        }
    }

    private func load() {
        if let s = supplement {
            name = s.name
            brand = s.brand
            dose = s.dose
            unit = s.unit
            slot = s.slot
            withFood = s.withFood
            specificDays = !s.takesEveryDay
            weekdays = s.weekdays
            clinicianDirected = s.clinicianDirected
            notes = s.notes
            catalogID = s.catalogID
            catalogName = s.name
        } else if let draft {
            name = draft.name
            if let u = draft.unit { unit = u }
            if let food = draft.withFood { withFood = food }
            if let s = draft.slot { slot = s }
            catalogID = draft.catalogID
            catalogName = draft.name
        }
    }

    /// Keeps the catalog link when the name is unchanged; otherwise looks the new name up.
    private func resolvedCatalogID(for trimmed: String) -> String? {
        if let catalogID, trimmed == catalogName { return catalogID }
        return Content.bestMatch(forName: trimmed)?.id
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let target: Supplement
        if let s = supplement {
            target = s
            s.name = trimmed
            s.brand = brand
            s.dose = dose
            s.unit = unit
            s.slot = slot
            s.withFood = withFood
        } else {
            target = Supplement(name: trimmed, brand: brand, dose: dose, unit: unit, slot: slot, withFood: withFood)
            context.insert(target)
        }
        target.frequencyRaw = specificDays ? "weekdays" : "daily"
        target.weekdays = specificDays ? weekdays : []
        target.clinicianDirected = clinicianDirected
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        target.catalogID = resolvedCatalogID(for: trimmed)
        try? context.save()
        Reminders.reschedule()
        onSaved?()
        dismiss()
    }

    private func delete() {
        if let s = supplement { context.delete(s) }
        try? context.save()
        Reminders.reschedule()
        dismiss()
    }
}

#if DEBUG
#Preview("Add") {
    SupplementForm(supplement: nil)
        .modelContainer(PreviewData.container(empty: true))
}

#Preview("From search") {
    SupplementForm(supplement: nil, draft: SupplementDraft(name: "Magnesium"))
        .modelContainer(PreviewData.container(empty: true))
}
#endif
