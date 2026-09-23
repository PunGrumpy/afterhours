import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    let prefs: Preferences

    var body: some View {
        TabView {
            PowerTab(model: model, prefs: prefs)
                .tabItem { Label("Power", systemImage: "bolt.fill") }
            AgentsTab(prefs: prefs)
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
                    Text("macOS ignores keep-awake requests when you close the lid. Installing adds a sudoers rule that allows Afterhours to run only `pmset -a disablesleep 0` and `pmset -a disablesleep 1`. macOS asks for your admin password once.")
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

            Section("Behavior") {
                Picker("Stay awake after agents finish", selection: $prefs.graceMinutes) {
                    Text("Off").tag(0)
                    ForEach([1, 2, 5, 10], id: \.self) { Text("\($0) min").tag($0) }
                }
                Toggle("Turn off the display when agents start", isOn: $prefs.turnDisplayOff)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AgentsTab: View {
    @Bindable var prefs: Preferences
    @State private var hookDirs = ClaudeHooks.configDirectories()
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
                            if on { prefs.detectedAgents.insert(kind.id) } else { prefs.detectedAgents.remove(kind.id) }
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
        }
        .formStyle(.grouped)
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
