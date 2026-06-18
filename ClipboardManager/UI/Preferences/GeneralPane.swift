// ClipboardManager/UI/Preferences/GeneralPane.swift
import SwiftUI

struct GeneralPane: View {
    @AppStorage(Settings.Key.appearance) private var appearanceRaw: String = AppAppearance.system.rawValue
    @AppStorage(Settings.Key.historyLimit) private var historyLimit: Int = 100
    @AppStorage(Settings.Key.retentionDays) private var retentionDays: Int = 90
    @AppStorage(Settings.Key.showHoverPreview) private var showHoverPreview: Bool = true
    @AppStorage(Settings.Key.compactMode) private var compactMode: Bool = false
    @AppStorage(Settings.Key.saveScreenshots) private var saveScreenshots: Bool = false
    @AppStorage(Settings.Key.annotationSaveFolder) private var annotationFolderData: Data?

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
                    Text("25").tag(25)
                    Text("50").tag(50)
                    Text("100").tag(100)
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
                Toggle(isOn: $compactMode) {
                    Text("Compact Mode")
                }
            }

            Section {
                Toggle(isOn: $saveScreenshots) {
                    Text("Save screenshots to history")
                }
            } header: {
                Text("Screenshots")
            } footer: {
                Text("When off, ⌘⇧A screenshots are copied to the clipboard for pasting but not saved into history.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("Annotation") {
                HStack {
                    Text("Save folder")
                    Spacer()
                    Text(AnnotationFolder.resolve(bookmark: annotationFolderData)
                            .lastPathComponent)
                        .foregroundStyle(.secondary)
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url,
                           let data = try? AnnotationFolder.makeBookmark(for: url) {
                            annotationFolderData = data
                        }
                    }
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
