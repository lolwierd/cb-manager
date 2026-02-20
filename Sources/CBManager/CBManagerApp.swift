import SwiftUI

@main
struct CBManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
