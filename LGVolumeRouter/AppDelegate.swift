import AppKit

@main
struct LGVolumeRouterApplication {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: RouterSettings!
    private var provider: WebOSProvider!
    private var router: VolumeRouter!
    private var menuBarController: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        settings = RouterSettings()
        provider = WebOSProvider(settings: settings.snapshot)
        router = VolumeRouter(settings: settings, provider: provider)
        menuBarController = MenuBarController(
            settings: settings,
            router: router,
            provider: provider
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
