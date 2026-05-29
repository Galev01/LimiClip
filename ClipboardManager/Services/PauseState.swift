// ClipboardManager/Services/PauseState.swift
import Foundation

/// A user-chosen pause duration for clipboard monitoring (the menu-bar
/// Pause submenu). Pure value logic — no AppKit — so it's unit-testable.
enum PauseChoice: CaseIterable {
    case fifteenMinutes
    case oneHour
    case untilResumed

    var menuTitle: String {
        switch self {
        case .fifteenMinutes: return "Pause for 15 Minutes"
        case .oneHour:        return "Pause for 1 Hour"
        case .untilResumed:   return "Pause Until Resumed"
        }
    }

    /// The instant monitoring should stay paused until, given "now".
    func pausedUntil(from now: Date) -> Date {
        switch self {
        case .fifteenMinutes: return now.addingTimeInterval(15 * 60)
        case .oneHour:        return now.addingTimeInterval(60 * 60)
        case .untilResumed:   return .distantFuture
        }
    }
}

/// Pure helpers for reasoning about the monitor's paused state and the
/// menu-bar icon that reflects it.
enum PauseState {
    /// Passing this to `PasteboardMonitor.pause(until:)` resumes immediately.
    static let resumeDate: Date = .distantPast

    static func isPaused(pausedUntil: Date, now: Date) -> Bool {
        now < pausedUntil
    }

    static func statusSymbolName(isPaused: Bool) -> String {
        isPaused ? "pause.circle" : "doc.on.clipboard"
    }
}
