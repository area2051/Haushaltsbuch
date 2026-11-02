import SwiftData
import SwiftUI
import HaushaltsbuchData
import HaushaltsbuchUI

@main
struct HaushaltsbuchApp: App {
    @State private var model: AppModel?
    private let startupError: String?

    init() {
        do {
            let container = try ModelContainer.makeAppContainer()
            _model = State(initialValue: AppModel(container: container, auth: AuthService()))
            startupError = nil
        } catch {
            _model = State(initialValue: nil)
            startupError = String(describing: error)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let model {
                RootView(model: model, initialServerAddress: Self.debugServerAddress)
            } else {
                ContentUnavailableView("Datenbank konnte nicht geöffnet werden",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(startupError ?? ""))
            }
        }
    }

    /// Nur Debug: Vorbelegung der Server-Eingabe per Launch-Argument
    /// `-HBServerAddress http://localhost:3000` (umgeht keine Anmeldung).
    private static var debugServerAddress: String {
        #if DEBUG
        UserDefaults.standard.string(forKey: "HBServerAddress") ?? ""
        #else
        ""
        #endif
    }
}
