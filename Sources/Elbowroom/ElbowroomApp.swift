import SwiftUI
import ElbowroomKit

@main
struct ElbowroomApp: App {
    @State private var model = AppModel()

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
        }

        Settings {
            ElbowroomSettingsView()
                .environment(model)
        }

        ///: the Guardian in the menu bar, wearing its Steward hat.
        MenuBarExtra {
            StewardMenu()
                .environment(model)
        } label: {
            Image(systemName: model.guardian.state.menuSymbol)
        }

        Window("About Elbowroom", id: "about") {
            AboutView()
                .environment(model)
        }
        .windowResizability(.contentSize)
    }
}
