import SwiftUI

@main
struct AfterhoursApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model, prefs: model.prefs)
        } label: {
            Image(nsImage: Mug.image(Mug.Mood(model.state)))
                .accessibilityLabel("Afterhours")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model, prefs: model.prefs)
        }
    }
}
