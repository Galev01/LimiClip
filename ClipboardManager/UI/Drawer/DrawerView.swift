import SwiftUI

struct DrawerView: View {
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        ZStack {
            // Vibrancy material under everything.
            VisualEffectBackground(material: DesignMaterials.drawer(dark: dark))

            // Gradient overlay matches the prototype's drawer body.
            LinearGradient(
                colors: dark
                    ? [Color(red: 52/255, green: 52/255, blue: 56/255).opacity(0.97),
                       Color(red: 32/255, green: 32/255, blue: 35/255).opacity(0.99)]
                    : [Color(red: 248/255, green: 248/255, blue: 252/255).opacity(0.97),
                       Color(red: 240/255, green: 240/255, blue: 245/255).opacity(0.99)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Phase 1: empty state placeholder. Phase 4 will replace this with
            // the top bar + card strip + bottom count bar.
            EmptyStateView()
        }
        .clipShape(.rect(topLeadingRadius: 16, topTrailingRadius: 16))
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                .stroke(DesignColors.hairline(dark: dark), lineWidth: 0.5)
        )
        .ignoresSafeArea()
    }
}

#Preview {
    DrawerView()
        .frame(width: 1440, height: 300)
        .preferredColorScheme(.dark)
}
