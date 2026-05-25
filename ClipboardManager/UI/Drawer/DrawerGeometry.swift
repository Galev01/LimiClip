import CoreGraphics

enum DrawerGeometry {
    /// Frame to use when the drawer is fully visible: full-width, anchored
    /// to the bottom edge of the screen's visible area.
    static func onScreenFrame(in screen: CGRect, height: CGFloat) -> CGRect {
        CGRect(x: screen.origin.x, y: screen.origin.y, width: screen.size.width, height: height)
    }

    /// Frame to use when the drawer is offscreen (slid down). One full
    /// drawer-height below the visible area.
    static func offScreenFrame(in screen: CGRect, height: CGFloat) -> CGRect {
        CGRect(x: screen.origin.x, y: screen.origin.y - height, width: screen.size.width, height: height)
    }
}
