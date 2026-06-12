import SwiftUI

@main
struct SnoopyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: appDelegate.model)
        } label: {
            Image(systemName: "camera.shutter.button")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var activityToken: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only: no Dock icon (also set via LSUIElement in Info.plist,
        // but this covers running the bare executable during development).
        NSApp.setActivationPolicy(.accessory)
        // Opt out of App Nap: a napped process gets hardware notifications
        // delivered late, which delays sounds after long idle periods. This
        // option still allows normal idle system sleep.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Deliver hardware event sounds promptly")
        model.start()
    }
}
