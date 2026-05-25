import SwiftUI

struct EmptyStateView: View {
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.primary.opacity(0.2))

            Text("Your clipboard is empty")
                .font(DesignTypography.emptyStateTitle)
                .foregroundStyle(.primary.opacity(dark ? 0.35 : 0.3))

            Text("Copy something to get started. Text, images, and files will appear here automatically.")
                .font(DesignTypography.emptyStateBody)
                .foregroundStyle(.primary.opacity(dark ? 0.2 : 0.18))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    EmptyStateView()
        .frame(width: 800, height: 300)
        .background(VisualEffectBackground(material: .hudWindow))
        .preferredColorScheme(.dark)
}
