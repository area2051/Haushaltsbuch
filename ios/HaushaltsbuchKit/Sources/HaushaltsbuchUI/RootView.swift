import SwiftUI

/// Wurzel der App: Onboarding/Anmeldung oder Hauptansicht (iPhone Tabs, iPad Seitenleiste).
public struct RootView: View {
    @State private var model: AppModel
    private let initialServerAddress: String
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    /// - Parameter initialServerAddress: Vorbelegung der Server-Eingabe (nur Debug-Builds nutzen sie).
    public init(model: AppModel, initialServerAddress: String = "") {
        _model = State(initialValue: model)
        self.initialServerAddress = initialServerAddress
    }

    public var body: some View {
        content
            .environment(model)
            .modelContainer(model.container)
            .appLockWindow(model.appLock)
            .onChange(of: scenePhase) { _, phase in
                model.scenePhaseChanged(phase)
            }
            .task {
                // Kaltstart mit Sperre: einmal automatisch fragen (danach über `scenePhaseChanged`).
                if scenePhase == .active { await model.appLock.autoPromptIfNeeded() }
            }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .onboarding:
            NavigationStack {
                switch model.visibleAuthState {
                case .needsSetup:
                    SetupView()
                case .needsLogin:
                    LoginView(prefill: model.loginPrefill)
                case .needsServer, .loggedIn:
                    ServerView(initialAddress: initialServerAddress)
                }
            }
        case .locked:
            NavigationStack {
                LoginView(prefill: model.loginPrefill)
            }
        case .ready:
            Group {
                if sizeClass == .compact {
                    MainTabView()
                } else {
                    MainSplitView()
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let engine = model.engine {
                    SyncStatusBanner(engine: engine)
                }
            }
        }
    }
}
