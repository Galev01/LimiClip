// ClipboardManager/UI/Drawer/HoverPreview.swift
import SwiftUI
import AppKit

struct HoverPreviewContent: View {
    let item: Item
    @Environment(\.blobStore) private var blobStore
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        Group {
            switch item.kind {
            case "image":
                if let path = item.blobPath,
                   let blobStore,
                   let nsImage = ImageCache.shared.image(forKey: path, url: blobStore.absoluteURL(forRelativePath: path)) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 380, maxHeight: 240)
                } else {
                    Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 380, height: 240)
                }
            case "file":
                fileBlock
            default:
                ScrollView {
                    Text(item.body)
                        .font(item.subtype == TextSubtype.code.rawValue || item.subtype == TextSubtype.json.rawValue
                              ? .system(size: 12, design: .monospaced)
                              : .system(size: 13))
                        .textSelection(.enabled)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 340, height: 240)
            }
        }
        .background(VisualEffectBackground(material: DesignMaterials.popover(dark: dark)))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DesignColors.hairline(dark: dark), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(dark ? 0.4 : 0.15), radius: 16, y: 8)
    }

    private var fileBlock: some View {
        let ref = try? FileReference.decodingJSON(item.body)
        return VStack(alignment: .leading, spacing: 6) {
            Text(ref?.name ?? "Unknown")
                .font(.system(size: 14, weight: .semibold))
            if let path = ref?.path {
                Text(path)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let size = ref?.formattedSize {
                Text(size)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}
