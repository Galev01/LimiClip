// ClipboardManager/UI/Preferences/ShortcutsPane.swift
import SwiftUI
import KeyboardShortcuts

struct ShortcutsPane: View {
    var body: some View {
        Form {
            Section("Global Hotkeys") {
                KeyboardShortcuts.Recorder("Toggle Clipboard Drawer", name: .toggleDrawer)
                KeyboardShortcuts.Recorder("Screenshot Region to Clipboard", name: .screenshotToClipboard)
            }

            Section("Compact Mode") {
                KeyboardShortcuts.Recorder("Open Compact Popup", name: .toggleCompactPopup)
            }

            Section("Chain Copy") {
                KeyboardShortcuts.Recorder("Append Selection to Clipboard", name: .chainCopyAppend)
                Text("Copies the selected text and adds it after the current clipboard text, separated by a space.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("Screen Recording") {
                KeyboardShortcuts.Recorder("Start / Stop Recording", name: .startRecording)
            }

            Section {
                Text("Click a shortcut and press the keys you want. Click the × to clear.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    ShortcutsPane()
        .frame(width: 400, height: 300)
}
