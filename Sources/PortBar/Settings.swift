import Carbon.HIToolbox
import Foundation

/// Global shortcut that opens the panel with the search field focused. A fixed set of presets keeps it simple.
enum Shortcut: String, CaseIterable, Identifiable {
    case ctrlOptP, optCmdP, ctrlOptCmdP, ctrlOptSpace, off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ctrlOptP: "⌃⌥P"
        case .optCmdP: "⌥⌘P"
        case .ctrlOptCmdP: "⌃⌥⌘P"
        case .ctrlOptSpace: "⌃⌥Space"
        case .off: "Off"
        }
    }

    var keyCode: UInt32 {
        self == .ctrlOptSpace ? UInt32(kVK_Space) : UInt32(kVK_ANSI_P)
    }

    var modifiers: UInt32 {
        switch self {
        case .ctrlOptP, .ctrlOptSpace: UInt32(controlKey | optionKey)
        case .optCmdP: UInt32(optionKey | cmdKey)
        case .ctrlOptCmdP: UInt32(controlKey | optionKey | cmdKey)
        case .off: 0
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var showStatusBarIcon: Bool { didSet { defaults.set(showStatusBarIcon, forKey: "showStatusBarIcon") } }
    @Published var shortcut: Shortcut { didSet { defaults.set(shortcut.rawValue, forKey: "shortcut") } }
    @Published var autoCheckUpdates: Bool { didSet { defaults.set(autoCheckUpdates, forKey: "autoCheckUpdates") } }

    init() {
        defaults.register(defaults: ["showStatusBarIcon": true, "autoCheckUpdates": true])
        showStatusBarIcon = defaults.bool(forKey: "showStatusBarIcon")
        shortcut = Shortcut(rawValue: defaults.string(forKey: "shortcut") ?? "") ?? .ctrlOptP
        autoCheckUpdates = defaults.bool(forKey: "autoCheckUpdates")
    }

    /// How to bring the panel back when the menu bar icon is hidden.
    var reopenHint: String {
        shortcut == .off
            ? "Open PortBar again from Spotlight or Applications to show this panel."
            : "Press \(shortcut.title) — or open PortBar from Spotlight — to show this panel."
    }
}
