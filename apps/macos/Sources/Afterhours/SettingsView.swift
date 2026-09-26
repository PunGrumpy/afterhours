import AfterhoursCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    let prefs: Preferences

    var body: some View {
        TabView {
            PowerTab(model: model, prefs: prefs)
                .tabItem { Label("Power", systemImage: "bolt.fill") }
            AgentsTab(model: model, prefs: prefs)
                .tabItem { Label("Agents", systemImage: "terminal") }
            GeneralTab(prefs: prefs)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 500)
        .frame(minHeight: 460)
    }
}

private struct PowerTab: View {
    let model: AppModel
    @Bindable var prefs: Preferences

    var body: some View {
        Form {
            Section {
                Toggle("Keep awake with the lid closed", isOn: $prefs.lidClosedMode)
                if model.lidControlInstalled {
                    LabeledContent("Lid-closed mode") {
                        HStack {
                            Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Button("Uninstall") { model.uninstallLidControl() }
                        }
                    }
                } else {
                    LabeledContent("Lid-closed mode") {
                        Button("Install…") { model.installLidControl() }
                    }
                    Text("When plugged in, a closed Mac stays awake without this. On battery, macOS ignores keep-awake requests when you close the lid. Installing adds a sudoers rule that allows Afterhours to run only `pmset -a disablesleep 0` and `pmset -a disablesleep 1`. macOS asks for an admin password once.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Lid")
            }

            Section("Battery safety") {
                Picker("Stop when battery is below", selection: $prefs.batteryThreshold) {
                    Text("Never").tag(0)
                    ForEach([5, 10, 15, 20, 30, 50], id: \.self) { Text("\($0)%").tag($0) }
                }
                Toggle("Only when plugged in", isOn: $prefs.onlyWhenPluggedIn)
                Toggle("Respect Low Power Mode", isOn: $prefs.respectLowPowerMode)
            }

            Section {
                Picker("When plugged in", selection: $prefs.pluggedInWaitMinutes) {
                    Text("Until sessions close").tag(Preferences.untilSessionsClose)
                    waitChoices([60, 30, 10, 1])
                }
                Picker("On battery", selection: $prefs.batteryWaitMinutes) {
                    waitChoices([120, 60, 30, 10, 1])
                }
            } header: {
                Text("Wait for you after agents finish")
            } footer: {
                Text("Keeps your Mac awake while you read and reply, so remote clients like T3 Code or SSH stay connected. The wait counts from when an agent last worked and ends early once every session closes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Display") {
                Toggle("Turn off the display when agents start", isOn: $prefs.turnDisplayOff)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func waitChoices(_ minutes: [Int]) -> some View {
        ForEach(minutes, id: \.self) { m in
            Text(m >= 60 ? "\(m / 60) hour\(m == 60 ? "" : "s")" : "\(m) min").tag(m)
        }
        Text("Don't wait").tag(0)
    }
}

private struct AgentsTab: View {
    let model: AppModel
    @Bindable var prefs: Preferences
    @State private var hookDirs = ClaudeHooks.configDirectories()
    @State private var addingHub = false
    @State private var refresh = 0
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                ForEach(hookDirs, id: \.path) { dir in
                    let installed = ClaudeHooks.isInstalled(in: dir)
                    LabeledContent {
                        Button(installed ? "Remove" : "Install") {
                            do {
                                try installed ? ClaudeHooks.uninstall(in: dir) : ClaudeHooks.install(in: dir)
                                error = nil
                            } catch {
                                self.error = error.localizedDescription
                            }
                            refresh += 1
                        }
                    } label: {
                        Label {
                            Text(dir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.body.monospaced())
                        } icon: {
                            Image(systemName: installed ? "checkmark.circle.fill" : "circle")
                        }
                    }
                }
                .id(refresh)
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Claude Code hooks")
            } footer: {
                Text("Hooks tell Afterhours when Claude Code is working, waiting for you, or idle. Restart open Claude Code sessions after installing. Afterhours backs up your original file to `settings.json.afterhours-backup`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(AgentKind.all) { kind in
                    Toggle(kind.displayName, isOn: Binding(
                        get: { prefs.detectedAgents.contains(kind.id) },
                        set: { on in
                            if on { prefs.disabledAgents.remove(kind.id) } else { prefs.disabledAgents.insert(kind.id) }
                        }
                    ))
                }
            } header: {
                Text("Process detection")
            } footer: {
                Text("Agents without hooks count as working while their processes use at least 3% of a CPU core, and for 45 seconds after that.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show subscription limits in the menu", isOn: $prefs.usageLimits)
            } header: {
                Text("Limits")
            } footer: {
                Text("Reads the Claude Code login from your Keychain with the `security` tool and the Codex login from `~/.codex/auth.json`, then asks Anthropic and OpenAI how much of each window is used. It checks when you open the menu and every 5 minutes while agents work. Afterhours never stores or refreshes a login.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach($prefs.hubs) { $hub in
                    LabeledContent {
                        HStack {
                            Toggle("Enabled", isOn: $hub.enabled).labelsHidden()
                            Button("Remove") { remove(hub) }
                        }
                    } label: {
                        Label {
                            Text(hub.label)
                            Text(hub.url).font(.caption).foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "server.rack")
                        }
                    }
                }
                Button("Add hub…") { addingHub = true }
            } header: {
                Text("Usage providers")
            } footer: {
                Text("A CLIProxyAPI hub pools several Claude Code or Codex accounts. Its management API lists them and makes the usage calls, so their quotas join the menu, pooled per provider. Afterhours only reads through it and keeps the management key in your Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
private struct AddHubSheet: View {
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
        VStack(alignment: .leading, spacing: 0) {
            Form {
                TextField("Label", text: $label, prompt: Text("Team hub"))
                TextField("URL", text: $url, prompt: Text("https://hub.example.com"))
                SecureField("Management key", text: $key)
                if let status {
                    Text(status).font(.caption).foregroundStyle(failed ? .red : .secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(checking ? "Checking…" : "Add") { Task { await add() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(checking || url.trimmingCharacters(in: .whitespaces).isEmpty || key.isEmpty)
            }
            .padding(20)
        }
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

private struct GeneralTab: View {
    @Bindable var prefs: Preferences
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            error = nil
                        } catch {
                            self.error = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                LabeledContent("Turn on or off") {
                    Text("⌥⌘L")
                }
            }

            Section("Alerts") {
                Toggle("Show notifications", isOn: $prefs.notifications)
                Picker("Sound", selection: $prefs.sound) {
                    Text("None").tag("")
                    ForEach(Preferences.sounds, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: prefs.sound) { _, name in
                    if !name.isEmpty { NSSound(named: NSSound.Name(name))?.play() }
                }
            }
        }
        .formStyle(.grouped)
    }
}
