// ClipboardManager/UI/Drawer/DrawerView.swift
import SwiftUI

struct DrawerView: View {
    @ObservedObject var viewModel: ClipboardViewModel

    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        ZStack {
            VisualEffectBackground(material: DesignMaterials.drawer(dark: dark))

            LinearGradient(
                colors: dark
                    ? [Color(red: 52/255, green: 52/255, blue: 56/255).opacity(0.97),
                       Color(red: 32/255, green: 32/255, blue: 35/255).opacity(0.99)]
                    : [Color(red: 248/255, green: 248/255, blue: 252/255).opacity(0.97),
                       Color(red: 240/255, green: 240/255, blue: 245/255).opacity(0.99)],
                startPoint: .top,
                endPoint: .bottom
            )

            if viewModel.items.isEmpty {
                EmptyStateView()
            } else {
                cardStrip
            }
        }
        .clipShape(.rect(topLeadingRadius: 16, topTrailingRadius: 16))
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                .stroke(DesignColors.hairline(dark: dark), lineWidth: 0.5)
        )
        .ignoresSafeArea()
    }

    private var cardStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewModel.items, id: \.id) { item in
                    ClipboardCard(item: item)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
    }
}

#Preview {
    let store = try! ClipboardStore(configuration: ClipboardStore.testingConfiguration())
    let vm = ClipboardViewModel(store: store)
    return DrawerView(viewModel: vm)
        .frame(width: 1440, height: 300)
        .preferredColorScheme(.dark)
}
