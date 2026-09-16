import SwiftUI
import ElbowroomKit

@main
struct ElbowroomApp: App {
    @State private var model = AppModel()
    @StateObject private var updater = Updater()

    var body: some Scene {
        // A Window scene, not a WindowGroup: one instrument, one window.
        // openWindow(id: "main") then summons instead of duplicating.
        Window("Elbowroom", id: "main") {
            Group {
                if model.inMain {
                    MainWindow()
                } else {
                    OnboardingView()
                }
            }
            .environment(model)
            .task { updater.start() }
            .background(WindowChrome(onboarding: !model.inMain))
            .tint(BColor.brand)
            .preferredColorScheme(
                model.settings.themeOverride == "dark" ? .dark
                : model.settings.themeOverride == "light" ? .light : nil
            )
        }
        .windowResizability(model.inMain ? .contentMinSize : .contentSize)
        .defaultSize(width: 1080, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button(Copy.checkForUpdates) { updater.check() }
                    .disabled(!updater.canCheck)
            }
        }

        Settings {
            ElbowroomSettingsView(automaticUpdates: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: { updater.automaticallyChecksForUpdates = $0 }
            ))
                .environment(model)
        }

        ///: the Steward in the menu bar, watching free space.
        MenuBarExtra {
            StewardMenu()
                .environment(model)
        } label: {
            Image(systemName: "internaldrive")
        }

        Window("About Elbowroom", id: "about") {
            AboutView()
                .environment(model)
        }
        .windowResizability(.contentSize)
    }
}
