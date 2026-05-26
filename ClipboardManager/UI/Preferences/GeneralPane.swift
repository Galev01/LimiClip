// ClipboardManager/UI/Preferences/GeneralPane.swift
import SwiftUI

struct GeneralPane: View {
    @AppStorage(Settings.Key.appearance) private var appearanceRaw: String = AppAppearance.system.rawValue
    @AppStorage(Settings.Key.historyLimit) private var historyLimit: Int = 5000
    @AppStorage(Settings.Key.retentionDays) private var retentionDays: Int = 90
    @AppStorage(Settings.Key.showHoverPreview) private var showHoverPreview: Bool = true

    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $launchAtLogin) {
                    Text("Launch at Login")
                }
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        try LaunchAtLogin.setEnabled(newValue)
                    } catch {
                        Log.app.error("launch at login toggle failed: \(error.localizedDescription, privacy: .public)")
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: $appearanceRaw) {
                    ForEach(AppAppearance.allCases) { a in
                        Text(a.label).tag(a.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("History") {
                Picker("Max items", selection: $historyLimit) {
                    Text("500").tag(500)
                    Text("1,000").tag(1000)
                    Text("5,000").tag(5000)
                    Text("10,000").tag(10000)
                    Text("Unlimited").tag(Int.max)
                }
                Picker("Keep for", selection: $retentionDays) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("Forever").tag(Int.max)
                }
            }

            Section("Drawer") {
                Toggle(isOn: $showHoverPreview) {
                    Text("Show preview on hover")
                }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    GeneralPane()
        .frame(width: 400, height: 500)
}
