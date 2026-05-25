// ClipboardManager/UI/Drawer/ClipboardCard.swift
import SwiftUI

struct ClipboardCard: View {
    let item: Item
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    private var isCode: Bool {
        item.subtype == TextSubtype.code.rawValue || item.subtype == TextSubtype.json.rawValue
    }

    private var isURL: Bool {
        item.subtype == TextSubtype.url.rawValue
    }

    var body: some View {
        VStack(spacing: 0) {
            // Content area
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)
                .mask(LinearGradient(
                    stops: [.init(color: .black, location: 0.65),
                            .init(color: .clear, location: 1.0)],
                    startPoint: .top, endPoint: .bottom))

            // Footer
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
        if isCode {
            Text(item.body)
                .font(DesignTypography.cardCode)
                .foregroundStyle(.primary.opacity(dark ? 0.8 : 0.7))
        } else if isURL {
            Text(item.body)
                .font(DesignTypography.cardBody)
                .underline()
                .foregroundStyle(.primary.opacity(dark ? 0.8 : 0.7))
        } else {
            Text(item.body)
                .font(DesignTypography.cardBody)
                .foregroundStyle(.primary.opacity(dark ? 0.8 : 0.7))
        }
    }

    private func relativeTime(_ epoch: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epoch))
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    let preview = Item(
        id: 1, kind: "text", subtype: "plain", contentHash: "abc",
        body: "Hello there, this is some text that wraps onto multiple lines so we can see the fade.",
        blobPath: nil, dimensions: nil, byteSize: 100,
        sourceApp: "Messages", sourceBundleId: "com.apple.MobileSMS",
        createdAt: Int64(Date().timeIntervalSince1970) - 120,
        pinned: false, snippetId: nil, deletedAt: nil
    )
    return ClipboardCard(item: preview)
        .padding()
        .preferredColorScheme(.dark)
}
