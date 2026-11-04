import CoreGraphics

/// How tall the menu may grow on a screen.
public enum MenuGeometry {
    private static let screenMargin: CGFloat = 8

    /// The menu hangs from the menu bar, so everything the screen leaves visible is its to fill, less a margin.
    public static func maximumHeight(visibleFrame: CGRect) -> CGFloat {
        max(1, visibleFrame.height - screenMargin)
    }
}
