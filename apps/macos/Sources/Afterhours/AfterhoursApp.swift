import AfterhoursCore
import SwiftUI

@main
struct AfterhoursApp: App {
    @State private var model: AppModel
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    /// `Afterhours --snapshot out.png [expanded] [crowded] [tall]` renders the menu with sample data and exits, so the
    /// design can be reviewed without clicking through the menu bar. `crowded` adds providers until all seven show;
    /// `tall` adds every agent and caps the menu's height at 620 points, so its middle scrolls.
    init() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot"), arguments.count > index + 1 {
            Self.snapshotMenu(to: arguments[index + 1], expanded: arguments.contains("expanded"),
                              crowded: arguments.contains("crowded"), tall: arguments.contains("tall"))
        }
        if let index = arguments.firstIndex(of: "--snapshot-settings"), arguments.count > index + 1 {
            Self.snapshotSettings(to: arguments[index + 1], page: arguments.dropFirst(index + 2).first ?? "general")
        }
        if let index = arguments.firstIndex(of: "--snapshot-motion"), arguments.count > index + 1 {
            Self.snapshotMotion(to: arguments[index + 1], flip: arguments.dropFirst(index + 2).first ?? "limits")
        }
        // Built only for a real run, because its init changes power settings and replaces the installed hook.
        _model = State(initialValue: AppModel())
    }

    private static func previewModel(expanded: Bool, crowded: Bool, tall: Bool = false) -> AppModel {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "app.afterhours.snapshot")!)
        prefs.limitsExpanded = expanded
        prefs.hubs = [UsageHub(id: "sample", label: "Thaipass", url: "https://thaipass-proxy.vercel.app")]
        return AppModel(preview: prefs, crowded: crowded, tall: tall)
    }

    /// The plain menu goes through ImageRenderer, which can't draw a scroll view, so `tall` renders in a real window.
    private static func snapshotMenu(to path: String, expanded: Bool, crowded: Bool, tall: Bool) -> Never {
        let model = previewModel(expanded: expanded, crowded: crowded, tall: tall)
        if tall {
            let menu = MenuView(model: model, prefs: model.prefs, snapshot: true, previewMaxHeight: 620)
            captureWindow(of: AnyView(menu), to: path, title: "Afterhours")
        }
        let renderer = ImageRenderer(content: MenuView(model: model, prefs: model.prefs, snapshot: true))
        renderer.scale = 2
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
        exit(0)
    }

    /// Controls backed by AppKit only draw inside a real window, so this shows one offscreen and captures its content.
    private static func captureWindow(of root: AnyView, to path: String, title: String) -> Never {
        // The capture below sees only what the content view draws, so paint the window's own color.
        let host = NSHostingController(rootView: root.background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentViewController: host)
        window.title = title
        window.toolbarStyle = .preference
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        if let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        exit(0)
    }

    /// Settings is built from AppKit controls, which only draw inside a real window. `page` is a tab
    /// name or "hub" for the add-hub sheet.
    private static func snapshotSettings(to path: String, page: String) -> Never {
        let model = previewModel(expanded: false, crowded: false)
        let root: AnyView = if page == "hub" {
            AnyView(AddHubSheet(model: model, prefs: model.prefs))
        } else {
            AnyView(SettingsView(model: model, prefs: model.prefs, tab: SettingsView.Tab(rawValue: page) ?? .general))
        }
        captureWindow(of: root, to: path, title: "Afterhours Settings")
    }

    private static let motionFrames = 8
    private static let motionSpan: TimeInterval = 0.32

    /// Flips one state (`limits`, `pool` or `pause`) in a hosted menu and writes frames of the change, each stamped with when it was captured.
    private static func snapshotMotion(to path: String, flip: String) -> Never {
        let model = previewModel(expanded: flip == "pool", crowded: false)
        let size = NSSize(width: 388, height: 780)
        let host = NSHostingView(rootView: MenuView(model: model, prefs: model.prefs, snapshot: true)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color(red: 0.16, green: 0.18, blue: 0.24)))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        let start = Date()
        switch flip {
        case "pause": model.preview(state: .paused(until: start.addingTimeInterval(30 * 60)))
        case "pool": click(window, at: NSPoint(x: 150, y: size.height - 507))
        default: model.prefs.limitsExpanded = true
        }
        var frames: [(milliseconds: Int, image: NSImage)] = []
        let bounds = host.bounds
        for index in 0..<motionFrames {
            RunLoop.main.run(until: start.addingTimeInterval(motionSpan * Double(index) / Double(motionFrames - 1)))
            let captured = Date()
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width), pixelsHigh: Int(bounds.height),
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            host.cacheDisplay(in: bounds, to: rep)
            let image = NSImage(size: size)
            image.addRepresentation(rep)
            frames.append((Int((captured.timeIntervalSince(start) * 1000).rounded()), image))
        }
        let strip = HStack(alignment: .top, spacing: 0) {
            ForEach(frames, id: \.milliseconds) { frame in
                VStack(spacing: 4) {
                    Image(nsImage: frame.image)
                    Text("\(frame.milliseconds) ms").font(.system(size: 14).monospacedDigit())
                }
            }
        }
        .padding(.bottom, 8)
        .background(Color(red: 0.16, green: 0.18, blue: 0.24))
        .foregroundStyle(.white)
        let renderer = ImageRenderer(content: strip)
        renderer.scale = 2
        if let tiff = renderer.nsImage?.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
        exit(0)
    }

    /// SwiftUI buttons aren't AppKit views and the accessibility tree stays empty without an assistive app,
    /// so the press is a mouse click at a point measured from the sample menu's layout.
    private static func click(_ window: NSWindow, at point: NSPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            else { continue }
            window.sendEvent(event)
        }
    }

    var body: some Scene {
        @Bindable var prefs = model.prefs
        MenuBarExtra(isInserted: $prefs.showInMenuBar) {
            MenuView(model: model, prefs: model.prefs)
        } label: {
            Image(nsImage: Mug.image(Mug.Mood(model.state)))
                .accessibilityLabel("Afterhours, \(model.state.spokenName.lowercasedFirst)")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model, prefs: model.prefs)
        }
    }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}

private extension HoldState {
    /// What VoiceOver reads for the menu bar icon, which shows the state only as a mug.
    var spokenName: String {
        switch self {
        case .holding: "Keeping your Mac awake"
        case .idle: "Idle"
        case .disabled: "Off"
        case .paused: "Paused"
        case .blocked: "Can't keep your Mac awake"
        }
    }
}

/// Opening Afterhours again while it runs shows Settings, the only way back when the menu bar icon is
/// hidden by you or by a crowded menu bar.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // SwiftUI offers `openSettings` only to views, so press the app menu's Settings item instead.
        guard let menu = NSApp.mainMenu?.items.first?.submenu,
              let index = menu.items.firstIndex(where: { $0.keyEquivalent == "," }) else { return true }
        NSApp.activate()
        menu.performActionForItem(at: index)
        return false
    }
}
