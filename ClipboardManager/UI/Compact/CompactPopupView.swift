// ClipboardManager/UI/Compact/CompactPopupView.swift
import SwiftUI

struct CompactPopupView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    let onPaste: (Item) -> Void
    let blobStore: BlobStore?

    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    private var items: [Item] {
        Array(viewModel.items.prefix(10))
    }

    var body: some View {
        ZStack {
            VisualEffectBackground(material: DesignMaterials.drawer(dark: dark))

            LinearGradient(
                colors: dark
                    ? [Color(red: 52/255, green: 52/255, blue: 56/255).opacity(0.97),
                       Color(red: 32/255, green: 32/255, blue: 35/255).opacity(0.99)]
                    : [Color(red: 248/255, green: 248/255, blue: 252/255).opacity(0.97),
                       Color(red: 240/255, green: 240/255, blue: 245/255).opacity(0.99)],
                startPoint: .top, endPoint: .bottom
            )

            if items.isEmpty {
                Text("No items yet")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(dark ? 0.3 : 0.25))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            CompactClipboardCard(item: item, onPaste: onPaste)
                            if idx < items.count - 1 {
                                Rectangle()
                                    .fill(DesignColors.hairline(dark: dark))
                                    .frame(height: 0.5)
                                    .padding(.leading, 50)
                            }
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DesignColors.hairline(dark: dark), lineWidth: 0.5)
        )
        .ignoresSafeArea()
        .environment(\.blobStore, blobStore)
    }
}

#Preview {
    if let store = try? ClipboardStore(configuration: ClipboardStore.testingConfiguration()) {
        let vm = ClipboardViewModel(store: store)
        CompactPopupView(viewModel: vm, onPaste: { _ in }, blobStore: nil)
            .frame(width: 300, height: 300)
            .preferredColorScheme(.dark)
    } else {
        Text("Preview unavailable")
    }
}
