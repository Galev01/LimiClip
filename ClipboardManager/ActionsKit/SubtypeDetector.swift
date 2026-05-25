// ClipboardManager/ActionsKit/SubtypeDetector.swift
import Foundation

/// Classifies text into a presentation subtype. Used at insert time only —
/// we record the detected subtype with the item so the UI doesn't have to
/// re-classify on every render.
enum TextSubtype: String, Codable, Sendable {
    case plain
    case url
    case json
    case code
}

enum SubtypeDetector {

    /// Heuristic classification, evaluated in order: URL → JSON → code → plain.
    static func detect(_ text: String) -> TextSubtype {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .plain }

        if isWholeStringURL(trimmed) { return .url }
        if isJSON(trimmed) { return .json }
        if looksLikeCode(trimmed) { return .code }
        return .plain
    }

    // MARK: - URL

    private static func isWholeStringURL(_ s: String) -> Bool {
        guard let url = URL(string: s),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host,
              host.contains(".")            // must have a TLD-like dot
        else { return false }
        // No internal whitespace. detect() already trimmed external whitespace.
        return !s.contains(where: { $0.isWhitespace })
    }

    // MARK: - JSON

    private static func isJSON(_ s: String) -> Bool {
        guard let first = s.first, (first == "{" || first == "["),
              let data = s.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }

    // MARK: - Code

    /// Looks for any of: language keywords near the start, common code punctuation,
    /// or shell prompt prefixes.
    private static func looksLikeCode(_ s: String) -> Bool {
        // Multi-line with braces or semicolons is a strong signal.
        let multiLine = s.contains("\n")
        let hasCodeChars = s.contains("{") && s.contains("}")
            || s.contains(";")
            || s.contains("=>")
            || s.contains("->")

        // First non-whitespace token starts with a keyword we recognise.
        let firstWord = s.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        let codeStarters: Set<String> = [
            "func", "def", "fn", "class", "struct", "enum", "interface", "type",
            "import", "from", "package", "module", "namespace",
            "const", "let", "var", "private", "public", "static", "final",
            "if", "for", "while", "switch", "case", "return", "throw", "try",
            "async", "await", "yield",
            "select", "insert", "update", "delete", "create", "drop", "alter",
            "SELECT", "INSERT", "UPDATE", "DELETE", "CREATE", "DROP", "ALTER",
        ]
        if codeStarters.contains(firstWord) { return true }

        // Shell pipelines / command lines often start with a known command.
        let shellStarters: Set<String> = [
            "brew", "npm", "yarn", "pnpm", "pip", "git", "docker",
            "curl", "wget", "ssh", "scp", "make", "cargo", "go", "python", "node", "ruby",
            "sudo", "open", "cd", "ls", "mv", "cp", "rm", "echo", "cat", "grep", "awk", "sed",
        ]
        if shellStarters.contains(firstWord) && hasCodeChars { return true }
        if shellStarters.contains(firstWord) && s.split(separator: " ").count > 1 { return true }

        // Heavy punctuation across multiple lines: probably code.
        if multiLine && hasCodeChars { return true }

        return false
    }
}
