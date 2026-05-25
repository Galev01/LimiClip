import AppKit

enum DesignMaterials {
    /// Material for the bottom drawer container. Dark = .hudWindow (heavier,
    /// more opaque vibrancy that survives a dark wallpaper); light = .popover.
    static func drawer(dark: Bool) -> NSVisualEffectView.Material {
        dark ? .hudWindow : .popover
    }

    /// Material for hover popovers and dropdowns.
    static func popover(dark: Bool) -> NSVisualEffectView.Material {
        .popover
    }

    /// Material for the preferences sidebar.
    static func sidebar(dark: Bool) -> NSVisualEffectView.Material {
        .sidebar
    }
}
