import Combine
import SwiftUI
import UIKit

/// Sperrbildschirm der Face-ID-Sperre.
struct LockScreen: View {
    @ObservedObject var lock: AppLock

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Haushaltsbuch ist gesperrt")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Button {
                Task { await lock.unlock() }
            } label: {
                Label("Entsperren", systemImage: "faceid")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(lock.isAuthenticating)
            .accessibilityIdentifier("lock.unlock")
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .accessibilityIdentifier("lockScreen")
    }
}

extension View {
    /// Zeigt den Sperrbildschirm in einem eigenen Fenster über allem (auch über Sheets und dem
    /// Teilen-Menü), solange `lock.isLocked`.
    func appLockWindow(_ lock: AppLock) -> some View {
        background(LockWindowInstaller(lock: lock).frame(width: 0, height: 0).accessibilityHidden(true))
    }
}

private struct LockWindowInstaller: UIViewRepresentable {
    let lock: AppLock

    func makeUIView(context: Context) -> LockWindowAnchorView {
        LockWindowAnchorView(lock: lock)
    }

    func updateUIView(_ uiView: LockWindowAnchorView, context: Context) {}
}

/// Legt beim Einhängen in ein Fenster ein zweites Fenster (Ebene über Alerts) in derselben Szene an
/// und blendet es je nach `isLocked` ein oder aus.
final class LockWindowAnchorView: UIView {
    private let lock: AppLock
    private var lockWindow: UIWindow?
    private var subscription: AnyCancellable?

    init(lock: AppLock) {
        self.lock = lock
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard lockWindow == nil, let scene = window?.windowScene else { return }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        let host = UIHostingController(rootView: LockScreen(lock: lock))
        w.rootViewController = host
        lockWindow = w
        subscription = lock.$isLocked
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] locked in
                MainActor.assumeIsolated { self?.setVisible(locked) }
            }
        setVisible(lock.isLocked)
    }

    private func setVisible(_ visible: Bool) {
        guard let lockWindow else { return }
        lockWindow.isHidden = !visible
        if !visible { window?.makeKey() }
    }
}
