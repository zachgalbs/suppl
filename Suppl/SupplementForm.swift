import SwiftUI
import SwiftData

struct SupplementForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let supplement: Supplement?

    @State private var name = ""
    @State private var brand = ""
    @State private var dose = 1.0
    @State private var unit = "capsule"
    @State private var slot = Slot.breakfast
    @State private var withFood = true
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

                if supplement != nil {
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
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || dose <= 0)
                }
            }
            .confirmationDialog("Remove \(name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Remove", role: .destructive, action: delete)
            }
            .onAppear(perform: load)
        }
    }

    private var suggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(Self.common, id: \.self) { item in
                    Button(item) { name = item }
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.sage.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding(.top, 8)
        }
    }

    private func load() {
        guard let s = supplement else { return }
        name = s.name
        brand = s.brand
        dose = s.dose
        unit = s.unit
        slot = s.slot
        withFood = s.withFood
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let s = supplement {
            s.name = trimmed
            s.brand = brand
            s.dose = dose
            s.unit = unit
            s.slot = slot
            s.withFood = withFood
        } else {
            context.insert(Supplement(name: trimmed, brand: brand, dose: dose, unit: unit, slot: slot, withFood: withFood))
        }
        try? context.save()
        Reminders.reschedule()
        dismiss()
    }

    private func delete() {
        if let s = supplement { context.delete(s) }
        try? context.save()
        Reminders.reschedule()
        dismiss()
    }
}
