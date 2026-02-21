import SwiftUI

@main
struct OhMyClawApp: App {
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra("Oh My Claw", systemImage: "tray.and.arrow.down.fill") {
            MenuBarView()
                .environment(coordinator)
        }
        .menuBarExtraStyle(.window)
    }
}
