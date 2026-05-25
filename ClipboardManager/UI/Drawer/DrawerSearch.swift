// ClipboardManager/UI/Drawer/DrawerSearch.swift
import SwiftUI

struct DrawerSearch: View {
    @Binding var query: String
    @Binding var expanded: Bool

    @FocusState private var fieldFocused: Bool
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(dark ? 0.4 : 0.35))

            if expanded {
                TextField("Search clipboard…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($fieldFocused)
                    .onSubmit { /* no-op: search filters live */ }
                    .onExitCommand {
                        query = ""
                        expanded = false
                        fieldFocused = false
                    }
                    .onChange(of: expanded) { _, isOn in
                        fieldFocused = isOn
                    }
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.primary.opacity(dark ? 0.4 : 0.35))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(width: expanded ? 220 : 32, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(dark ? 0.08 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(expanded
                    ? Color.primary.opacity(dark ? 0.15 : 0.1)
                    : Color.clear,
                    lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !expanded { expanded = true }
        }
        .animation(.easeOut(duration: 0.2), value: expanded)
        .onAppear {
            if expanded { fieldFocused = true }
        }
    }
}

#Preview {
    @Previewable @State var q = ""
    @Previewable @State var expanded = true
    return DrawerSearch(query: $q, expanded: $expanded)
        .padding()
        .preferredColorScheme(.dark)
}
