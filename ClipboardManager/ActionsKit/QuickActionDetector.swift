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

        if let url = match.url {
            let absoluteString = url.absoluteString
            if absoluteString.hasPrefix("mailto:") {
                let address = String(absoluteString.dropFirst("mailto:".count))
                return address.isEmpty ? nsText.substring(with: match.range) : address
            }
            if let host = url.host {
                let user = url.user ?? ""
                return user.isEmpty ? nsText.substring(with: match.range) : "\(user)@\(host)"
            }
        }
        return nsText.substring(with: match.range)
            .replacingOccurrences(of: "mailto:", with: "")
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
