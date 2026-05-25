// ClipboardManager/UI/Drawer/DrawerView.swift
import SwiftUI

struct DrawerView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    let blobStore: BlobStore?

    var onPaste: ((Item, Bool) -> Void)? = nil
    var onCopy: ((Item) -> Void)? = nil
    var onDelete: ((Item) -> Void)? = nil
    var onOpenURL: ((Item) -> Void)? = nil
    var onRevealInFinder: ((Item) -> Void)? = nil

    @State private var searchExpanded: Bool = false

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
                startPoint: .top, endPoint: .bottom
            )

            VStack(spacing: 0) {
                topBar
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
                            onRevealInFinder: { onRevealInFinder?($0) }
                        )
                            .id(item.id ?? -1)
                            .onTapGesture {
                                viewModel.jumpTo(index: idx)
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
