import Foundation
import ServiceManagement

// Registers launch-at-login via the app bundle, so macOS's Login Items / "Allow in the Background"
// list shows the app name ("CDT Usage") instead of the signing team name.
enum LoginItem {
    static func enable() {
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.register()
        }
    }

    static func disable() {
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.unregister()
        }
    }
}
