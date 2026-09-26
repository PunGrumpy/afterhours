import SwiftUI

@main
struct AfterhoursApp: App {
    @State private var model = AppModel()

    /// `Afterhours --snapshot out.png [expanded]` renders the menu with sample data and exits, so the
    /// design can be reviewed without clicking through the menu bar.
    init() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--snapshot"), arguments.count > index + 1 else { return }
        let prefs = Preferences(defaults: UserDefaults(suiteName: "app.afterhours.snapshot")!)
        prefs.limitsExpanded = arguments.contains("expanded")
        let model = AppModel(preview: prefs)
        let renderer = ImageRenderer(content: MenuView(model: model, prefs: prefs, snapshot: true))
        renderer.scale = 2
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: arguments[index + 1]))
        }
        exit(0)
    }

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
