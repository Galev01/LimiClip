// ClipboardManager/UI/Compact/CompactClipboardCard.swift
import SwiftUI
import AppKit

struct CompactClipboardCard: View {
    let item: Item
    let onPaste: (Item) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.blobStore) private var blobStore
    @State private var isHovered = false

    private var dark: Bool { scheme == .dark }

    var body: some View {
        Button(action: { onPaste(item) }) {
            HStack(spacing: 10) {
                iconView
                    .frame(width: 28, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryLabel)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary.opacity(dark ? 0.85 : 0.75))
                    if let secondary = secondaryLabel {
                        Text(secondary)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                Text(relativeTime(item.createdAt))
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(dark ? 0.3 : 0.25))
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .background(
                isHovered
                    ? Color.primary.opacity(dark ? 0.08 : 0.06)
                    : Color.clear
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var iconView: some View {
        if item.kind == "image" {
            imageThumb
        } else if item.kind == "file" {
            let ref = try? FileReference.decodingJSON(item.body)
            let ext = ref?.fileExtension ?? ""
            Image(systemName: symbolName(for: ext))
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(colorForExtension(ext))
        } else {
            let symbol: String = {
                if item.subtype == TextSubtype.url.rawValue { return "link" }
                if item.subtype == TextSubtype.code.rawValue || item.subtype == TextSubtype.json.rawValue {
                    return "chevron.left.forwardslash.chevron.right"
                }
                return "doc.text"
            }()
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(DesignColors.accent)
        }
    }

    @ViewBuilder
    private var imageThumb: some View {
        if let path = item.blobPath,
           let blobStore,
           let nsImage = NSImage(contentsOf: blobStore.absoluteURL(forRelativePath: path)) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: "photo")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(DesignColors.accent)
        }
    }

    private var primaryLabel: String {
        if item.kind == "file" {
            return (try? FileReference.decodingJSON(item.body))?.name ?? "File"
        }
        return String(item.body.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var secondaryLabel: String? {
        if item.kind == "image" { return item.dimensions }
        if item.kind == "file" {
            return (try? FileReference.decodingJSON(item.body))?.formattedSize
        }
        if item.subtype == TextSubtype.url.rawValue { return "URL" }
        if item.subtype == TextSubtype.code.rawValue || item.subtype == TextSubtype.json.rawValue { return "Code" }
        return nil
    }

    private func symbolName(for ext: String) -> String {
        switch ext {
        case "pdf":                                             return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "heic", "tiff":      return "photo"
        case "mp4", "mov", "m4v":                              return "film"
        case "mp3", "wav", "m4a", "aiff":                     return "music.note"
        case "zip", "tar", "gz", "7z":                        return "doc.zipper"
        case "fig":                                            return "paintbrush"
        case "sketch":                                         return "scribble"
        case "key", "pages", "numbers":                       return "doc.text"
        case "xlsx", "csv":                                    return "tablecells"
        case "docx", "rtf", "txt", "md":                      return "doc.text"
        default:                                               return "doc"
        }
    }

    private func colorForExtension(_ ext: String) -> Color {
        switch ext {
        case "pdf":                                            return .red
        case "fig":                                            return .purple
        case "sketch":                                         return .orange
        case "key":                                            return .blue
        case "xlsx", "csv":                                    return .green
        case "docx":                                           return .blue
        case "zip", "tar", "gz", "7z":                        return .gray
        case "png", "jpg", "jpeg", "gif", "heic", "tiff":     return .pink
        case "mp4", "mov", "m4v":                             return .purple
        default:                                               return .secondary
        }
    }

    private func relativeTime(_ epoch: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epoch))
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}

#Preview("Text item") {
    let item = Item(
        id: 1, kind: "text", subtype: "plain", contentHash: "a",
        body: "Hello world — this is a clipboard item",
        blobPath: nil, dimensions: nil, byteSize: 50,
        sourceApp: "Safari", sourceBundleId: nil,
        createdAt: Int64(Date().timeIntervalSince1970) - 90,
        pinned: false, snippetId: nil, deletedAt: nil
    )
    return CompactClipboardCard(item: item, onPaste: { _ in })
        .frame(width: 300)
        .preferredColorScheme(.dark)
}

#Preview("URL item") {
    let item = Item(
        id: 2, kind: "text", subtype: TextSubtype.url.rawValue, contentHash: "b",
        body: "https://apple.com/swift",
        blobPath: nil, dimensions: nil, byteSize: 30,
        sourceApp: "Chrome", sourceBundleId: nil,
        createdAt: Int64(Date().timeIntervalSince1970) - 300,
        pinned: false, snippetId: nil, deletedAt: nil
    )
    return CompactClipboardCard(item: item, onPaste: { _ in })
        .frame(width: 300)
        .preferredColorScheme(.light)
}
