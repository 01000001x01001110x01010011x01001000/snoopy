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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only: no Dock icon (also set via LSUIElement in Info.plist,
        // but this covers running the bare executable during development).
        NSApp.setActivationPolicy(.accessory)
        model.start()
    }
}
