import CoreGraphics

public enum MenuGeometry {
    /// Leaves a gap above the bottom of the screen, as macOS menus do.
    private static let screenMargin: CGFloat = 8
    private static let shareOfScreen: CGFloat = 0.85

    /// The tallest the menu may grow: the room under its top edge, and never more than most of the screen.
    public static func maximumHeight(windowTop: CGFloat, visibleFrame: CGRect) -> CGFloat {
        let roomBelowTop = windowTop - visibleFrame.minY - screenMargin
        let aestheticCap = (visibleFrame.height * shareOfScreen).rounded(.down)
        return max(1, min(roomBelowTop, aestheticCap))
    }
}
