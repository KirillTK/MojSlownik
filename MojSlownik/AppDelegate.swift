import UIKit

/// Registers the Home Screen quick actions and routes them into `QuickActionStore`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.shortcutItems = QuickAction.allCases.map(\.shortcutItem)
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = QuickActionSceneDelegate.self
        return configuration
    }
}

/// SwiftUI owns the window; this delegate only receives quick actions (cold launch and while running).
@MainActor
final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Set by the app at launch; scene delegates are created by UIKit and cannot be injected.
    static weak var store: QuickActionStore?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let item = connectionOptions.shortcutItem else { return }
        Self.store?.handle(shortcutType: item.type)
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(Self.store?.handle(shortcutType: shortcutItem.type) ?? false)
    }
}
