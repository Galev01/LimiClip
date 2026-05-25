import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global shortcut that toggles the bottom drawer. Default: ⌘⇧V.
    static let toggleDrawer = Self("toggleDrawer", default: .init(.v, modifiers: [.command, .shift]))
}

@MainActor
final class HotkeyService {
    private let onToggle: @MainActor () -> Void

    init(onToggle: @escaping @MainActor () -> Void) {
        self.onToggle = onToggle
    }

    func start() {
        KeyboardShortcuts.onKeyDown(for: .toggleDrawer) { [weak self] in
            Log.hotkey.info("toggleDrawer fired")
            self?.onToggle()
        }
    }

    func stop() {
        KeyboardShortcuts.removeAllHandlers()
    }
}
