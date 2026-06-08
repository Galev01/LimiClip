// ClipboardManager/UI/Preferences/PreferencesView.swift
import SwiftUI

enum PreferencesPane: String, CaseIterable, Identifiable {
    case general
    case shortcuts
    case privacy

    var id: String { rawValue }
    var label: String {
        switch self {
        case .general:   return "General"
        case .shortcuts: return "Shortcuts"
        case .privacy:   return "Privacy"
        }
    }
    var symbol: String {
        switch self {
        case .general:   return "gearshape"
        case .shortcuts: return "keyboard"
        case .privacy:   return "hand.raised"
        }
    }
}

struct PreferencesView: View {
    let exclusionsVM: ExclusionsViewModel

    @State private var selected: PreferencesPane = .general

    init(exclusionsVM: ExclusionsViewModel) {
        self.exclusionsVM = exclusionsVM
    }

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
                case .privacy:   PrivacyPane(viewModel: exclusionsVM)
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle(selected.label)
        }
    }
}

#Preview {
    if let store = try? ClipboardStore(configuration: ClipboardStore.testingConfiguration()) {
        let vm = ExclusionsViewModel(store: store)
        PreferencesView(exclusionsVM: vm)
            .frame(width: 600, height: 400)
    } else {
        Text("Preview unavailable")
    }
}
