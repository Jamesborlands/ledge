import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage("shakeEnabled") private var shakeEnabled = false
    @AppStorage("notchEnabled") private var notchEnabled = true
    @AppStorage("shakeSensitivity") private var sensitivity = 1
    @AppStorage("removeAfterDrag") private var removeAfterDrag = false
    @AppStorage("historyLimit") private var historyLimit = 50
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Opening a shelf") {
                Toggle("Drag a file up to the notch to open a shelf", isOn: $notchEnabled)
                Toggle("Shake the mouse while dragging to open a shelf", isOn: $shakeEnabled)
                Picker("Shake sensitivity", selection: $sensitivity) {
                    Text("Low").tag(0)
                    Text("Medium").tag(1)
                    Text("High").tag(2)
                }
                .disabled(!shakeEnabled)
                LabeledContent("New shelf", value: "⌥⇧D")
                LabeledContent("New shelf from clipboard", value: "⌥⇧V")
            }
            Section("Shelves") {
                Toggle("Remove items from the shelf after dragging them out", isOn: $removeAfterDrag)
                Stepper("Keep up to \(historyLimit) recent shelves", value: $historyLimit, in: 10...200, step: 10)
            }
            Section("General") {
                Toggle("Open Ledge at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        loginError = LoginItem.set(newValue)
                        launchAtLogin = LoginItem.isEnabled
                    }))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns an error message, or nil on success.
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return "Couldn't change the login item: \(error.localizedDescription)"
        }
    }
}
