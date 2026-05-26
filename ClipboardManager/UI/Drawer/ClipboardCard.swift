// ClipboardManager/UI/Drawer/ClipboardCard.swift
import SwiftUI
import AppKit

struct ClipboardCard: View {
    let item: Item
    var isFocused: Bool = false
    var onPaste: ((Item, Bool) -> Void)? = nil
    var onCopy: ((Item) -> Void)? = nil
    var onDelete: ((Item) -> Void)? = nil
    var onOpenURL: ((Item) -> Void)? = nil
    var onRevealInFinder: ((Item) -> Void)? = nil
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
                .stroke(
                    isFocused
                        ? DesignColors.accent
                        : DesignColors.hairline(dark: dark),
                    lineWidth: isFocused ? 2 : 0.5
                )
        )
        .shadow(color: isFocused
                    ? DesignColors.accent.opacity(0.25)
                    : Color.clear,
                radius: 12, y: 4)
        .contextMenu {
            Button("Paste") { onPaste?(item, false) }
                .keyboardShortcut(.return, modifiers: [])
            Button("Paste as Plain Text") { onPaste?(item, true) }
                .keyboardShortcut(.return, modifiers: .shift)
            Button("Copy") { onCopy?(item) }
                .keyboardShortcut("c", modifiers: .command)
            Divider()
            if item.subtype == TextSubtype.url.rawValue {
                Button("Open URL") { onOpenURL?(item) }
            }
            if item.kind == "file" {
                Button("Reveal in Finder") { onRevealInFinder?(item) }
            }
            Divider()
            Button("Delete", role: .destructive) { onDelete?(item) }
        }
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
            Image(systemName: FileTypeStyle.symbolName(for: ref?.fileExtension ?? ""))
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(FileTypeStyle.color(for: ref?.fileExtension ?? ""))
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
