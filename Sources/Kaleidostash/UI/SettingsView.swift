import SwiftUI

struct SettingsView: View {
    let model: AppModel
    var body: some View {
        Form {
            Section {
                Toggle("Sync every 6 hours", isOn: Binding(get: { model.scheduleOn }, set: model.setSchedule))
                    .disabled(model.scheduling)
            } footer: { Text("Runs in the background, even when Kaleidostash is closed.") }
        }
        .formStyle(.grouped).frame(width: 420).fixedSize(horizontal: false, vertical: true)
        .alert("Couldn't Change the Schedule", isPresented: Binding(get: { model.scheduleError != nil },
                    set: { if !$0 { model.scheduleError = nil } })) {
            Button("OK") { model.scheduleError = nil }
        } message: { Text(model.scheduleError ?? "") }
    }
}
