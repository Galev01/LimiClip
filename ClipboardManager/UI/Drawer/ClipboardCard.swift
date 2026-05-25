// ClipboardManager/UI/Drawer/ClipboardCard.swift
import SwiftUI
import AppKit

struct ClipboardCard: View {
    let item: Item
    @Environment(\.colorScheme) private var scheme
    @Environment(\.blobStore) private var blobStore

    private var dark: Bool { scheme == .dark }

    private var isCode: Bool {
        item.subtype == TextSubtype.code.rawValue || item.subtype == TextSubtype.json.rawValue
    }
    private var isURL: Bool {
        item.subtype == TextSubtype.url.rawValue
    }
    private var isImage: Bool { item.kind == "image" }
    private var isFile: Bool { item.kind == "file" }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipShape(.rect(topLeadingRadius: 12, topTrailingRadius: 12))

            footer
        }
        .frame(width: 184, height: 210)
        .background(DesignColors.cardBackground(dark: dark))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DesignColors.hairline(dark: dark), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var content: some View {
        if isImage {
            imageContent
        } else if isFile {
            fileContent
        } else {
            textContent
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        ZStack(alignment: .bottomTrailing) {
            if let path = item.blobPath,
               let blobStore,
               let nsImage = NSImage(contentsOf: blobStore.absoluteURL(forRelativePath: path)) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Rectangle()
                    .fill(LinearGradient(colors: [.gray.opacity(0.4), .gray.opacity(0.2)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            if let dims = item.dimensions {
                Text(dims)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.4))
                    .clipShape(Capsule())
                    .padding(8)
            }
        }
    }

    @ViewBuilder
    private var fileContent: some View {
        let ref = (try? FileReference.decodingJSON(item.body))
        VStack(spacing: 8) {
            Image(systemName: symbolName(for: ref?.fileExtension ?? ""))
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(colorForExtension(ref?.fileExtension ?? ""))
            Text(ref?.name ?? "Unknown file")
                .font(DesignTypography.cardBody)
                .foregroundStyle(.primary.opacity(dark ? 0.85 : 0.75))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            if let size = ref?.formattedSize {
                Text(size)
                    .font(DesignTypography.cardFooterTime)
                    .foregroundStyle(.primary.opacity(dark ? 0.4 : 0.35))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var textContent: some View {
        Group {
            if isCode {
                Text(item.body)
                    .font(DesignTypography.cardCode)
            } else if isURL {
                Text(item.body)
                    .font(DesignTypography.cardBody)
                    .underline()
            } else {
                Text(item.body)
                    .font(DesignTypography.cardBody)
            }
        }
        .foregroundStyle(.primary.opacity(dark ? 0.8 : 0.7))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .mask(LinearGradient(
            stops: [.init(color: .black, location: 0.65),
                    .init(color: .clear, location: 1.0)],
            startPoint: .top, endPoint: .bottom))
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.secondary.opacity(0.6))
                .frame(width: 10, height: 10)
            Text(item.sourceApp ?? "Unknown")
                .font(DesignTypography.cardFooterApp)
                .foregroundStyle(.primary.opacity(dark ? 0.5 : 0.4))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(relativeTime(item.createdAt))
                .font(DesignTypography.cardFooterTime)
                .foregroundStyle(.primary.opacity(dark ? 0.3 : 0.25))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(DesignColors.hairline(dark: dark)),
                 alignment: .top)
    }

    private func symbolName(for ext: String) -> String {
        switch ext {
        case "pdf":                       return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "heic", "tiff": return "photo"
        case "mp4", "mov", "m4v":         return "film"
        case "mp3", "wav", "m4a", "aiff": return "music.note"
        case "zip", "tar", "gz", "7z":    return "doc.zipper"
        case "fig":                       return "paintbrush"
        case "sketch":                    return "scribble"
        case "key", "pages", "numbers":   return "doc.text"
        case "xlsx", "csv":               return "tablecells"
        case "docx", "rtf", "txt", "md":  return "doc.text"
        default:                          return "doc"
        }
    }

    private func colorForExtension(_ ext: String) -> Color {
        switch ext {
        case "pdf":                       return .red
        case "fig":                       return .purple
        case "sketch":                    return .orange
        case "key":                       return .blue
        case "xlsx", "csv":               return .green
        case "docx":                      return .blue
        case "zip", "tar", "gz", "7z":    return .gray
        case "png", "jpg", "jpeg", "gif", "heic", "tiff": return .pink
        case "mp4", "mov", "m4v":         return .purple
        default:                          return .secondary
        }
    }

    private func relativeTime(_ epoch: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epoch))
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}

#Preview("Text") {
    let preview = Item(
        id: 1, kind: "text", subtype: "plain", contentHash: "abc",
        body: "Hello there, this is some text that wraps onto multiple lines.",
        blobPath: nil, dimensions: nil, byteSize: 100,
        sourceApp: "Messages", sourceBundleId: nil,
        createdAt: Int64(Date().timeIntervalSince1970) - 120,
        pinned: false, snippetId: nil, deletedAt: nil
    )
    return ClipboardCard(item: preview)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("File") {
    let ref = FileReference(path: "/U/x/Q2 Report.pdf", name: "Q2 Report.pdf", byteSize: 2_457_600, modifiedAt: 1)
    let body = try! ref.encodedJSON()
    let preview = Item(
        id: 2, kind: "file", subtype: nil, contentHash: "h",
        body: body, blobPath: nil, dimensions: nil, byteSize: Int(ref.byteSize),
        sourceApp: "Finder", sourceBundleId: nil,
        createdAt: Int64(Date().timeIntervalSince1970) - 30,
        pinned: false, snippetId: nil, deletedAt: nil
    )
    return ClipboardCard(item: preview)
        .padding()
        .preferredColorScheme(.dark)
}
