import CoreGraphics
import Testing
@testable import AfterhoursCore

@Test func menuFillsTheVisibleScreenLessAMargin() {
    let visible = CGRect(x: 0, y: 90, width: 1440, height: 780)
    #expect(MenuGeometry.maximumHeight(visibleFrame: visible) == 772)
}

@Test func menuHeightStaysPositiveOnADegenerateScreen() {
    #expect(MenuGeometry.maximumHeight(visibleFrame: CGRect(x: 0, y: 0, width: 100, height: 4)) == 1)
}
