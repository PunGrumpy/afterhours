import Foundation
import Testing
@testable import AfterhoursCore

private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

@Test func theMenuMayUseMostOfTheScreenWhenThereIsRoom() {
    // 982 * 0.85 = 834.7, under the 970 - 8 of room below the menu bar.
    #expect(MenuGeometry.maximumHeight(windowTop: 970, visibleFrame: screen) == 834)
}

@Test func theMenuStopsShortOfTheBottomOfTheScreen() {
    #expect(MenuGeometry.maximumHeight(windowTop: 500, visibleFrame: screen) == 492)
}

@Test func theBottomEdgeIsTheDockNotTheScreen() {
    let aboveDock = CGRect(x: 0, y: 80, width: 1512, height: 902)
    #expect(MenuGeometry.maximumHeight(windowTop: 500, visibleFrame: aboveDock) == 412)
}

@Test func theMenuIsNeverShorterThanOnePoint() {
    #expect(MenuGeometry.maximumHeight(windowTop: 3, visibleFrame: screen) == 1)
    #expect(MenuGeometry.maximumHeight(windowTop: -100, visibleFrame: screen) == 1)
}
