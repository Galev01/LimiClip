// ClipboardManager/UI/Preferences/PrivacyPane.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PrivacyPane: View {
    @ObservedObject var viewModel: ExclusionsViewModel

    var body: some View {
        Form {
            Section {
                if viewModel.exclusions.isEmpty {
                    Text("No apps excluded. Clipboard history records copies from all apps.")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                } else {
                    ForEach(viewModel.exclusions, id: \.bundleId) { exclusion in
                        HStack {
                            Label(exclusion.name, systemImage: "app.badge.checkmark")
                            Spacer()
                            Button(role: .destructive) {
                                viewModel.remove(bundleId: exclusion.bundleId)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Remove \(exclusion.name) from exclusions")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Excluded Apps")
                    Spacer()
                    Button("Add App…") {
                        addAppFromPanel()
                    }
                    .font(.system(size: 12))
                }
            } footer: {
                Text("Clipboard history will not record copies made in excluded apps.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - NSOpenPanel

    private func addAppFromPanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Application"
        panel.prompt = "Exclude"
        panel.message = "Select an app to exclude from clipboard history:"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let (bundleId, name) = extractBundleInfo(from: url) else {
            Log.app.warning("PrivacyPane: could not read Info.plist from \(url.path, privacy: .public)")
            return
        }

        viewModel.add(bundleId: bundleId, name: name)
    }

    private func extractBundleInfo(from appURL: URL) -> (bundleId: String, name: String)? {
        let plistURL = appURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Info.plist")

        guard
            let dict = NSDictionary(contentsOf: plistURL),
            let bundleId = dict["CFBundleIdentifier"] as? String,
            !bundleId.isEmpty
        else { return nil }

        let name = (dict["CFBundleDisplayName"] as? String)
            ?? (dict["CFBundleName"] as? String)
            ?? appURL.deletingPathExtension().lastPathComponent

        return (bundleId, name)
    }
}

#Preview {
    let store = try! ClipboardStore(configuration: ClipboardStore.testingConfiguration())
    try! store.addExclusion(bundleId: "com.agilebits.onepassword7", name: "1Password 7")
    try! store.addExclusion(bundleId: "com.bitwarden.desktop", name: "Bitwarden")
    let vm = ExclusionsViewModel(store: store)
    return PrivacyPane(viewModel: vm)
        .frame(width: 400, height: 400)
}
