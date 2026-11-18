import AppKit
import Combine
import ServiceManagement
import SwiftUI

final class SettingsWindowController {
    private let settings: AppSettings
    private let store: ClipboardStore
    private var window: NSWindow?

    init(settings: AppSettings, store: ClipboardStore) {
        self.settings = settings
        self.store = store
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: settings, store: store))
            let window = NSWindow(contentViewController: hosting)
            window.title = "MacClipboard Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
        store.refreshDiskUsage()
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: ClipboardStore

    @State private var canPaste = Accessibility.canPaste
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var confirmErase = false
    @State private var errorMessage: String?

    private let refresh = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section("General") {
                Toggle("Save clipboard history", isOn: $settings.isEnabled)
                Picker("History size", selection: $settings.historyLimit) {
                    ForEach(AppSettings.historyLimitOptions, id: \.self) { Text("\($0) items").tag($0) }
                }
                Toggle("Keep history after restart", isOn: $settings.keepAfterRestart)
                Picker("Shortcut", selection: $settings.shortcut) {
                    ForEach(Shortcut.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            }

            Section {
                Toggle("Ignore copies from password managers", isOn: $settings.ignorePasswordManagers)
                LabeledContent("Stored") {
                    Text("\(store.items.count) items · \(ByteCountFormatter.string(fromByteCount: Int64(store.diskUsage), countStyle: .file))")
                }
                Button("Erase All History…", role: .destructive) { confirmErase = true }
            } header: {
                Text("Privacy & Security")
            } footer: {
                Text("History stays on this Mac. It is encrypted (AES-256-GCM) with a key kept in your Keychain and excluded from Time Machine. MacClipboard makes no network connections. Pinned items don't count toward the history size.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let problem = store.storageProblem {
                Section {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                LabeledContent("Accessibility") {
                    if canPaste {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Allow…") {
                            Accessibility.requestAccess()
                            Accessibility.openSettings()
                        }
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Needed to paste the item you pick straight into the app you're using. Without it, picking an item only copies it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("About") {
                LabeledContent("Version", value: version)
                LabeledContent("Author", value: "Anil Prajapati Newa")
                if let copyright = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String {
                    Text(copyright).font(.footnote).foregroundStyle(.secondary)
                }
                Link("Source code on GitHub", destination: URL(string: "https://github.com/anil3a/macClipboard")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .frame(minHeight: 560)
        .onReceive(refresh) { _ in
            canPaste = Accessibility.canPaste
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .confirmationDialog("Erase all clipboard history?", isPresented: $confirmErase) {
            Button("Erase All", role: .destructive) { store.eraseAll() }
        } message: {
            Text("This removes every item, including pinned ones. It can't be undone.")
        }
        .alert("Couldn't change Launch at Login", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = "\(error.localizedDescription)\n\nMove MacClipboard.app to the Applications folder and try again."
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
