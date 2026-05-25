// ClipboardManager/UI/Drawer/DrawerTabBar.swift
import SwiftUI

struct DrawerTabBar: View {
    @Binding var selectedTab: DrawerTab
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DrawerTab.allCases) { tab in
                tabButton(for: tab)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(dark ? 0.06 : 0.04))
        )
    }

    private func tabButton(for tab: DrawerTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            tabButtonLabel(for: tab)
        }
        .buttonStyle(.plain)
    }

    private func tabButtonLabel(for tab: DrawerTab) -> some View {
        Text(tab.label)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .foregroundStyle(
                selectedTab == tab
                    ? Color.primary.opacity(dark ? 0.95 : 0.85)
                    : Color.primary.opacity(dark ? 0.45 : 0.4)
            )
            .background(
                selectedTab == tab
                    ? Color.primary.opacity(dark ? 0.12 : 0.08)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

#Preview {
    @Previewable @State var tab: DrawerTab = .all
    return DrawerTabBar(selectedTab: $tab)
        .padding()
        .preferredColorScheme(.dark)
}
