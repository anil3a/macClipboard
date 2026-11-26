import Foundation

/// User preferences, saved in UserDefaults.
final class AppSettings: ObservableObject {
    static let historyLimitOptions = [20, 50, 100, 200, 300]
    static let defaultHistoryLimit = 50

    private enum Key {
        static let enabled = "historyEnabled"
        static let limit = "historyLimit"
        static let keepAfterRestart = "keepHistoryAfterRestart"
        static let ignorePasswordManagers = "ignorePasswordManagers"
        static let shortcut = "shortcut"
        static let panelHeight = "panelHeight"
    }

    private let defaults: UserDefaults

    /// Record new copies.
    @Published var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Key.enabled) } }
    /// Maximum number of unpinned items (pinned items don't count).
    @Published var historyLimit: Int { didSet { defaults.set(historyLimit, forKey: Key.limit) } }
    @Published var keepAfterRestart: Bool { didSet { defaults.set(keepAfterRestart, forKey: Key.keepAfterRestart) } }
    @Published var ignorePasswordManagers: Bool { didSet { defaults.set(ignorePasswordManagers, forKey: Key.ignorePasswordManagers) } }
    @Published var shortcut: Shortcut { didSet { defaults.set(shortcut.rawValue, forKey: Key.shortcut) } }
    /// Height of the history panel, set by dragging its bottom edge. 0 means the default.
    var panelHeight: Double {
        get { defaults.double(forKey: Key.panelHeight) }
        set { defaults.set(newValue, forKey: Key.panelHeight) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabled: true,
            Key.limit: Self.defaultHistoryLimit,
            Key.keepAfterRestart: true,
            Key.ignorePasswordManagers: true,
        ])
        isEnabled = defaults.bool(forKey: Key.enabled)
        let limit = defaults.integer(forKey: Key.limit)
        historyLimit = Self.historyLimitOptions.contains(limit) ? limit : Self.defaultHistoryLimit
        keepAfterRestart = defaults.bool(forKey: Key.keepAfterRestart)
        ignorePasswordManagers = defaults.bool(forKey: Key.ignorePasswordManagers)
        shortcut = defaults.string(forKey: Key.shortcut).flatMap(Shortcut.init(rawValue:)) ?? .shiftCommandV
    }
}
