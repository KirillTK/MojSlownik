import UIKit

/// Home Screen quick actions (long press on the app icon). Registered as dynamic shortcut items so their
/// titles come from the String Catalog.
enum QuickAction: String, CaseIterable {
    case scanText = "scan-text"

    private static let typePrefix = "MojSlownik.quickAction."

    var shortcutType: String { Self.typePrefix + rawValue }

    init?(shortcutType: String) {
        guard shortcutType.hasPrefix(Self.typePrefix) else { return nil }
        self.init(rawValue: String(shortcutType.dropFirst(Self.typePrefix.count)))
    }

    var title: String {
        switch self {
        case .scanText: return String(localized: "Scan text")
        }
    }

    var symbolName: String {
        switch self {
        case .scanText: return "camera.viewfinder"
        }
    }

    var shortcutItem: UIApplicationShortcutItem {
        UIApplicationShortcutItem(type: shortcutType, localizedTitle: title, localizedSubtitle: nil,
                                  icon: UIApplicationShortcutIcon(systemImageName: symbolName))
    }
}
