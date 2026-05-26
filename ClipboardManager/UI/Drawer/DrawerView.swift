// ClipboardManager/UI/Drawer/DrawerView.swift
import AppKit
import SwiftUI

struct DrawerView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    let blobStore: BlobStore?

    var onPaste: ((Item, Bool) -> Void)? = nil
    var onCopy: ((Item) -> Void)? = nil
    var onDelete: ((Item) -> Void)? = nil
    var onOpenURL: ((Item) -> Void)? = nil
    var onRevealInFinder: ((Item) -> Void)? = nil
    var onPin: ((Item, Bool) -> Void)? = nil

    var accessibilityCheck: () -> Bool = { true }

    /// Refresh tick used to recompute live values (Accessibility permission,
    /// etc.) without relying on @State + .onAppear (which only fires once
    /// even though our window orders out / front repeatedly). Bumped on a
    /// timer below.
    @State private var refreshTick: Int = 0

    @AppStorage(Settings.Key.showHoverPreview) private var showHoverPreview: Bool = true

    @State private var searchExpanded: Bool = false
    @State private var hoveredID: Int64? = nil
    @State private var hoverTimer: DispatchWorkItem? = nil
    @State private var debouncedHoveredItem: Item? = nil

    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    /// Live-read on every body evaluation so the banner disappears the moment
    /// the user grants the permission in System Settings (no reopen needed).
    /// The `refreshTick` reference forces SwiftUI to re-invoke the closure
    /// once per second via the timer below.
    private var accessibilityGranted: Bool {
        _ = refreshTick
        return accessibilityCheck()
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

            VStack(spacing: 0) {
                topBar
                if !accessibilityGranted {
                    accessibilityBanner
                }
                Spacer(minLength: 0)
                if viewModel.filteredItems.isEmpty {
                    if viewModel.items.isEmpty && viewModel.searchQuery.isEmpty && viewModel.selectedTab == .all {
                        EmptyStateView()
                    } else {
                        Text(viewModel.searchQuery.isEmpty
                             ? "No items in this tab"
                             : "No results for \"\(viewModel.searchQuery)\"")
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(dark ? 0.3 : 0.25))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    cardStrip
                }
                Spacer(minLength: 0)
                bottomBar
            }
        }
        .clipShape(.rect(topLeadingRadius: 16, topTrailingRadius: 16))
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                .stroke(DesignColors.hairline(dark: dark), lineWidth: 0.5)
        )
        .environment(\.blobStore, blobStore)
        .ignoresSafeArea()
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            refreshTick &+= 1
        }
        .overlay(alignment: .top) {
            if let hovered = debouncedHoveredItem, showHoverPreview {
                HoverPreviewContent(item: hovered)
                    .padding(.top, 56)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .animation(.easeOut(duration: 0.18), value: debouncedHoveredItem?.id)
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            DrawerSearch(query: $viewModel.searchQuery, expanded: $searchExpanded)
            Spacer(minLength: 16)
            DrawerTabBar(selectedTab: $viewModel.selectedTab)
            Spacer(minLength: 16)
            kbdHint
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var kbdHint: some View {
        HStack(spacing: 4) {
            Text("⌘⇧V")
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(dark ? 0.08 : 0.05))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(dark ? 0.08 : 0.06), lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text("toggle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary.opacity(dark ? 0.25 : 0.2))
        }
    }

    private var cardStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(viewModel.filteredItems.enumerated()), id: \.element.id) { idx, item in
                        ClipboardCard(
                            item: item,
                            isFocused: idx == viewModel.focusedIndex,
                            onPaste: { onPaste?($0, $1) },
                            onCopy: { onCopy?($0) },
                            onDelete: { onDelete?($0) },
                            onOpenURL: { onOpenURL?($0) },
                            onRevealInFinder: { onRevealInFinder?($0) },
                            onPin: { onPin?($0, $1) }
                        )
                            .id(item.id ?? -1)
                            .onTapGesture(count: 2) {
                                onPaste?(item, false)
                            }
                            .onTapGesture {
                                viewModel.jumpTo(index: idx)
                            }
                            .onHover { hovering in
                                guard showHoverPreview else { return }
                                hoverTimer?.cancel()
                                if hovering {
                                    let snapshot = item
                                    let work = DispatchWorkItem {
                                        debouncedHoveredItem = snapshot
                                        hoveredID = snapshot.id
                                    }
                                    hoverTimer = work
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
                                } else if hoveredID == item.id {
                                    debouncedHoveredItem = nil
                                    hoveredID = nil
                                }
                            }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .onChange(of: viewModel.focusedIndex) { _, newIndex in
                let list = viewModel.filteredItems
                guard list.indices.contains(newIndex), let id = list[newIndex].id else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private var accessibilityBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Auto-paste needs Accessibility permission")
                    .font(.system(size: 12, weight: .semibold))
                Text("Without it, Enter only copies to the clipboard. Grant access in System Settings → Privacy & Security → Accessibility.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(dark ? 0.12 : 0.1))
        )
        .padding(.horizontal, 20)
    }

    private var bottomBar: some View {
        HStack {
            let count = viewModel.filteredItems.count
            let total = viewModel.items.count
            Text(viewModel.searchQuery.isEmpty
                 ? "\(count) item\(count == 1 ? "" : "s")"
                 : "\(count) of \(total) matched")
            Spacer()
            Text("⏎ paste · ⌫ delete · / search")
        }
        .font(.system(size: 11))
        .foregroundStyle(.primary.opacity(dark ? 0.2 : 0.18))
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }
}

#Preview {
    let store = try! ClipboardStore(configuration: ClipboardStore.testingConfiguration())
    let vm = ClipboardViewModel(store: store)
    return DrawerView(viewModel: vm, blobStore: nil)
        .frame(width: 1440, height: 300)
        .preferredColorScheme(.dark)
}
