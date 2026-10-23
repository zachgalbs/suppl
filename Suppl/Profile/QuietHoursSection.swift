import SwiftUI
import SupplCore

/// Quiet hours. Automatic (-1) runs from after the bedtime reminder until the wake reminder.
struct QuietHoursSection: View {
    @AppStorage(PrefKey.quietStart) private var quietStart = -1
    @AppStorage(PrefKey.quietEnd) private var quietEnd = -1

    private var isAutomatic: Bool { quietStart < 0 || quietEnd < 0 }

    private var automatic: Binding<Bool> {
        Binding(
            get: { isAutomatic },
            set: { on in
                if on {
                    quietStart = -1
                    quietEnd = -1
                } else {
                    // Start from what automatic would have used, so nothing changes until the user edits it.
                    let bedtimeEnd = MomentWindow.defaultWindow(for: .bedtime).after
                    let wakeStart = MomentWindow.defaultWindow(for: .wake).before
                    quietStart = (Slot.bedtime.minutes + bedtimeEnd) % (24 * 60)
                    quietEnd = (Slot.wake.minutes - wakeStart + 24 * 60) % (24 * 60)
                }
            }
        )
    }

    var body: some View {
        Section {
            Toggle("Automatic", isOn: automatic)
            if !isAutomatic {
                DatePicker("Starts", selection: $quietStart.asTime, displayedComponents: .hourAndMinute)
                DatePicker("Ends", selection: $quietEnd.asTime, displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Quiet hours")
        } footer: {
            Text(isAutomatic
                 ? "From after your bedtime reminder until you usually wake up. No reminders arrive during quiet hours."
                 : "No reminders arrive during quiet hours.")
        }
    }
}

#if DEBUG
#Preview {
    Form {
        QuietHoursSection()
    }
}
#endif
