import AfterhoursCore
import SwiftUI

@main
struct AfterhoursApp: App {
    @State private var model = AppModel()

    /// `Afterhours --snapshot out.png [expanded]` renders the menu with sample data and exits, so the
    /// design can be reviewed without clicking through the menu bar.
    init() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot"), arguments.count > index + 1 {
            Self.snapshotMenu(to: arguments[index + 1], expanded: arguments.contains("expanded"))
        }
        if let index = arguments.firstIndex(of: "--snapshot-settings"), arguments.count > index + 1 {
            Self.snapshotSettings(to: arguments[index + 1], page: arguments.dropFirst(index + 2).first ?? "general")
        }
    }

    private static func previewModel(expanded: Bool) -> AppModel {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "app.afterhours.snapshot")!)
        prefs.limitsExpanded = expanded
        prefs.hubs = [UsageHub(id: "sample", label: "Thaipass", url: "https://thaipass-proxy.vercel.app")]
        return AppModel(preview: prefs)
    }

    private static func snapshotMenu(to path: String, expanded: Bool) -> Never {
        let model = previewModel(expanded: expanded)
        let renderer = ImageRenderer(content: MenuView(model: model, prefs: model.prefs, snapshot: true))
        renderer.scale = 2
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
        exit(0)
    }

    /// Settings is built from AppKit controls, which only draw inside a real window. `page` is a tab
    /// name or "hub" for the add-hub sheet.
    private static func snapshotSettings(to path: String, page: String) -> Never {
        let model = previewModel(expanded: false)
        let root: AnyView = if page == "hub" {
            AnyView(AddHubSheet(model: model, prefs: model.prefs))
        } else {
            AnyView(SettingsView(model: model, prefs: model.prefs, tab: SettingsView.Tab(rawValue: page) ?? .general))
        }
        // The capture below sees only what the content view draws, so paint the window's own color.
        let host = NSHostingController(rootView: root.background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentViewController: host)
        window.title = "Afterhours Settings"
        window.toolbarStyle = .preference
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        if let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
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
