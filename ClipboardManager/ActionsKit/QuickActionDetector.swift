// ClipboardManager/ActionsKit/QuickActionDetector.swift
import Foundation

// MARK: - QuickAction

enum QuickAction: Equatable, Sendable {
    case call(String)
    case composeEmail(String)
    case copyHexColor(String)
}

// MARK: - QuickActionDetector

enum QuickActionDetector {

    static func detect(in text: String) -> [QuickAction] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var actions: [QuickAction] = []

        if let phone = detectPhone(in: trimmed) {
            actions.append(.call(phone))
        }
        if let email = detectEmail(in: trimmed) {
            actions.append(.composeEmail(email))
        }
        if let hex = detectHexColor(in: trimmed) {
            actions.append(.copyHexColor(hex))
        }

        return actions
    }

    // MARK: - Phone detection

    private static func detectPhone(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue) else {
            return nil
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = detector.matches(in: text, options: [], range: range)

        guard matches.count == 1, let match = matches.first else { return nil }

        let coverage = Double(match.range.length) / Double(nsText.length)
        guard coverage >= 0.5 else { return nil }

        if let phoneNumber = match.phoneNumber {
            return phoneNumber
        }
        return nsText.substring(with: match.range)
    }

    // MARK: - Email detection

    private static func detectEmail(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = detector.matches(in: text, options: [], range: range)

        let emailMatches = matches.filter {
            $0.url?.scheme == "mailto" || $0.url?.absoluteString.hasPrefix("mailto:") == true
        }
        guard emailMatches.count == 1, let match = emailMatches.first else { return nil }

        let coverage = Double(match.range.length) / Double(nsText.length)
        guard coverage >= 0.5 else { return nil }

        let rawCandidate: String
        if let abs = match.url?.absoluteString, abs.hasPrefix("mailto:") {
            rawCandidate = String(abs.dropFirst("mailto:".count))
        } else {
            rawCandidate = nsText.substring(with: match.range)
        }
        let cleaned = rawCandidate.isEmpty ? nsText.substring(with: match.range) : rawCandidate
        return sanitizedEmailAddress(cleaned)
    }

    /// Reduces a detected candidate to a safe bare email address, or nil if it
    /// can't be. Strips any mailto query (`?cc=…`) and rejects header/param
    /// injection characters and malformed addresses, so the address can be
    /// handed to a `mailto:` URL without smuggling cc/bcc/subject/body.
    internal static func sanitizedEmailAddress(_ candidate: String) -> String? {
        // Drop any query string — the cc/bcc/subject/body injection vector.
        let base = String(candidate.prefix(while: { $0 != "?" }))
        // Reject param separators and any whitespace / control characters.
        let forbidden = CharacterSet(charactersIn: "?&;%").union(.whitespacesAndNewlines)
        guard base.rangeOfCharacter(from: forbidden) == nil else { return nil }
        // Require local@domain shape with a dotted, non-edge-dotted domain.
        let parts = base.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let local = parts[0], domain = parts[1]
        guard !local.isEmpty,
              domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix(".")
        else { return nil }
        return base
    }

    // MARK: - Hex color detection

    private static let hexRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: "^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$")
    }()

    private static func detectHexColor(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard hexRegex.firstMatch(in: text, options: [], range: range) != nil else {
            return nil
        }
        return text
    }
}
