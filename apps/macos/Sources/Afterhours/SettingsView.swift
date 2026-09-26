import AfterhoursCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    enum Tab: String, CaseIterable {
        case general, power, agents, limits
    }

    let model: AppModel
    let prefs: Preferences
    @State private var tab: Tab

    init(model: AppModel, prefs: Preferences, tab: Tab = .general) {
        self.model = model
        self.prefs = prefs
        _tab = State(initialValue: tab)
    }

    /// Every tab reports its own height, so the window fits the tab you're on.
    var body: some View {
        TabView(selection: $tab) {
            GeneralTab(prefs: prefs)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            PowerTab(model: model, prefs: prefs)
                .tabItem { Label("Power", systemImage: "bolt.fill") }
                .tag(Tab.power)
            AgentsTab(prefs: prefs)
                .tabItem { Label("Agents", systemImage: "terminal") }
                .tag(Tab.agents)
            LimitsTab(model: model, prefs: prefs)
                .tabItem { Label("Limits", systemImage: "gauge.with.dots.needle.33percent") }
                .tag(Tab.limits)
        }
        .frame(width: 500)
    }
}

/// The page layout every tab shares.
private struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 24) { content }
            .padding(20)
            .frame(width: 500, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @Bindable var prefs: Preferences
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var error: String?

    var body: some View {
        SettingsPage {
            SettingsSection {
                SettingsToggle(title: "Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            error = nil
                        } catch {
                            self.error = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                SettingsRow("Turn Afterhours on or off") {
                    Text("⌥⌘L").foregroundStyle(.secondary)
                }
            } footer: {
                if let error { Text(error).foregroundStyle(.red) }
            }

            SettingsSection("Alerts") {
                SettingsToggle(title: "Show notifications", isOn: $prefs.notifications)
                SettingsRow("Sound") {
                    Picker("Sound", selection: $prefs.sound) {
                        Text("None").tag("")
                        Divider()
                        ForEach(Preferences.sounds, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: prefs.sound) { _, name in
                        if !name.isEmpty { NSSound(named: NSSound.Name(name))?.play() }
                    }
                }
            }

            SettingsSection("Display") {
                SettingsToggle(title: "Turn off the display when agents start", isOn: $prefs.turnDisplayOff)
            }
        }
    }
}

// MARK: - Power

private struct PowerTab: View {
    let model: AppModel
    @Bindable var prefs: Preferences

    var body: some View {
        SettingsPage {
            SettingsSection("Lid") {
                SettingsToggle(title: "Keep awake with the lid closed", isOn: $prefs.lidClosedMode)
                SettingsRow("Lid-closed mode on battery") {
                    if model.lidControlInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Button("Uninstall") { model.uninstallLidControl() }
                    } else {
                        Button("Install…") { model.installLidControl() }
                    }
                }
            } footer: {
                Text("Plugged in, a closed Mac stays awake without this. On battery, macOS ignores keep-awake requests once the lid closes, so installing adds a sudoers rule that lets Afterhours run only `pmset -a disablesleep 0` and `pmset -a disablesleep 1`. macOS asks for an admin password once.")
            }

            SettingsSection("Battery safety") {
                SettingsRow("Stop when battery is below") {
                    Picker("Stop when battery is below", selection: $prefs.batteryThreshold) {
                        Text("Never").tag(0)
                        Divider()
                        ForEach([5, 10, 15, 20, 30, 50], id: \.self) { Text("\($0)%").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsToggle(title: "Only when plugged in", isOn: $prefs.onlyWhenPluggedIn)
                SettingsToggle(title: "Respect Low Power Mode", isOn: $prefs.respectLowPowerMode)
            }

            SettingsSection("Wait for you after agents finish") {
                SettingsRow("When plugged in") {
                    Picker("When plugged in", selection: $prefs.pluggedInWaitMinutes) {
                        Text("Until sessions close").tag(Preferences.untilSessionsClose)
                        Divider()
                        waitChoices([60, 30, 10, 1])
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsRow("On battery") {
                    Picker("On battery", selection: $prefs.batteryWaitMinutes) {
                        waitChoices([120, 60, 30, 10, 1])
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            } footer: {
                Text("Keeps your Mac awake while you read and reply, so remote clients like T3 Code or SSH stay connected. The wait counts from when an agent last worked and ends early once every session closes.")
            }
        }
    }

    @ViewBuilder
    private func waitChoices(_ minutes: [Int]) -> some View {
        ForEach(minutes, id: \.self) { m in
            Text(m >= 60 ? "\(m / 60) hour\(m == 60 ? "" : "s")" : "\(m) min").tag(m)
        }
        Divider()
        Text("Don't wait").tag(0)
    }
}

// MARK: - Agents

private struct AgentsTab: View {
    @Bindable var prefs: Preferences
    @State private var hookDirs = ClaudeHooks.configDirectories()
    @State private var refresh = 0
    @State private var error: String?

    var body: some View {
        SettingsPage {
            SettingsSection("Claude Code hooks") {
                ForEach(hookDirs, id: \.path) { dir in
                    let installed = ClaudeHooks.isInstalled(in: dir)
                    SettingsRow {
                        Label {
                            Text(dir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).monospaced()
                        } icon: {
                            Image(systemName: installed ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(installed ? .green : .secondary)
                        }
                    } control: {
                        Button(installed ? "Remove" : "Install") { toggleHooks(in: dir, installed: installed) }
                    }
                }
                .id(refresh)
            } footer: {
                if let error { Text(error).foregroundStyle(.red) }
                Text("Hooks tell Afterhours when Claude Code is working, waiting for you, or idle. Restart open Claude Code sessions after installing. Your original file is kept as `settings.json.afterhours-backup`.")
            }

            SettingsSection("Process detection") {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                          alignment: .leading, spacing: 10) {
                    ForEach(AgentKind.all) { kind in
                        Toggle(kind.displayName, isOn: Binding(
                            get: { prefs.detectedAgents.contains(kind.id) },
                            set: { on in
                                if on { prefs.disabledAgents.remove(kind.id) } else { prefs.disabledAgents.insert(kind.id) }
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(.vertical, 12)
                .settingsRow()
            } footer: {
                Text("Agents without hooks count as working while their processes use at least 3% of a CPU core, and for 45 seconds after that.")
            }
        }
    }

    private func toggleHooks(in dir: URL, installed: Bool) {
        do {
            try installed ? ClaudeHooks.uninstall(in: dir) : ClaudeHooks.install(in: dir)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        refresh += 1
    }
}

// MARK: - Limits

private struct LimitsTab: View {
    let model: AppModel
    @Bindable var prefs: Preferences
    @State private var addingHub = false

    var body: some View {
        SettingsPage {
            SettingsSection {
                SettingsToggle(title: "Show subscription limits in the menu", isOn: $prefs.usageLimits)
            } footer: {
                Text("Reads the Claude Code login from your Keychain with the `security` tool and the Codex login from `~/.codex/auth.json`, then asks Anthropic and OpenAI how much of each window is left. It checks when you open the menu and every 5 minutes while agents work, and never stores or refreshes a login.")
            }

            SettingsSection("Usage providers") {
                ForEach($prefs.hubs) { $hub in
                    SettingsRow {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hub.label)
                                Text(hub.url).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "server.rack")
                        }
                    } control: {
                        Toggle("Enabled", isOn: $hub.enabled).toggleStyle(.switch).labelsHidden().controlSize(.small)
                        Button("Remove") { remove(hub) }
                    }
                }
                Button { addingHub = true } label: {
                    Label("Add CLIProxyAPI hub…", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .settingsRow()
            } footer: {
                Text("A CLIProxyAPI hub pools several Claude Code or Codex accounts. Its management API lists them and makes the usage calls, so their quotas join the menu, pooled per provider. Afterhours only reads through it and keeps the management key in your Keychain.")
            }
        }
        .sheet(isPresented: $addingHub) { AddHubSheet(model: model, prefs: prefs) }
        .onChange(of: prefs.hubs.map(\.enabled)) { model.refreshUsage(minimumAge: 0) }
    }

    private func remove(_ hub: UsageHub) {
        hub.deleteManagementKey()
        prefs.hubs.removeAll { $0.id == hub.id }
        model.refreshUsage(minimumAge: 0)
    }
}

/// Checks the hub answers with the key before anything is saved.
struct AddHubSheet: View {
    let model: AppModel
    @Bindable var prefs: Preferences
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var url = ""
    @State private var key = ""
    @State private var status: String?
    @State private var failed = false
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a CLIProxyAPI hub").font(.headline)
            Form {
                TextField("Label", text: $label, prompt: Text("Team hub"))
                TextField("URL", text: $url, prompt: Text("https://hub.example.com"))
                SecureField("Management key", text: $key)
            }
            .formStyle(.columns)
            Text("Afterhours asks the hub for its account list before saving, then keeps the key in your Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if let status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(failed ? .red : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(checking ? "Checking…" : "Add") { Task { await add() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(checking || url.trimmingCharacters(in: .whitespaces).isEmpty || key.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func add() async {
        checking = true
        defer { checking = false }
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        switch await UsageLimits.hubAccountCount(url: trimmedURL, managementKey: trimmedKey) {
        case .failure(let error):
            failed = true
            status = error.message
            return
        case .success(0):
            failed = true
            status = "The hub answered, but pools no Claude Code or Codex accounts."
            return
        case .success:
            break
        }
        let name = label.trimmingCharacters(in: .whitespaces)
        let hub = UsageHub(label: name.isEmpty ? (URL(string: trimmedURL)?.host ?? trimmedURL) : name, url: trimmedURL)
        guard hub.saveManagementKey(trimmedKey) else {
            failed = true
            status = "Couldn't save the key to your Keychain."
            return
        }
        prefs.hubs.append(hub)
        model.refreshUsage(minimumAge: 0)
        dismiss()
    }
}
