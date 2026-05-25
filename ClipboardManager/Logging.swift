// ClipboardManager/Logging.swift
import OSLog

enum Log {
    static let subsystem = "dev.gallev.ClipboardManager"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let drawer = Logger(subsystem: subsystem, category: "drawer")
    static let menuBar = Logger(subsystem: subsystem, category: "menu-bar")
    static let coordinator = Logger(subsystem: subsystem, category: "coordinator")
}
