// ClipboardManager/UI/Preferences/PreferencesView.swift
import SwiftUI

enum PreferencesPane: String, CaseIterable, Identifiable {
    case general
    case shortcuts

    var id: String { rawValue }
    var label: String {
        switch self {
        case .general: return "General"
        case .shortcuts: return "Shortcuts"
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        }
    }
}

struct PreferencesView: View {
    @State private var selected: PreferencesPane = .general

    var body: some View {
        NavigationSplitView {
            List(PreferencesPane.allCases, selection: $selected) { pane in
                Label(pane.label, systemImage: pane.symbol)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
            .listStyle(.sidebar)
        } detail: {
            Group {
                switch selected {
                case .general:   GeneralPane()
                case .shortcuts: ShortcutsPane()
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle(selected.label)
        }
    }
}

#Preview {
    PreferencesView()
        .frame(width: 600, height: 400)
}
