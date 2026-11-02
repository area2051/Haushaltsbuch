import Foundation
import SwiftUI
import Testing
@testable import HaushaltsbuchUI

/// Fake für Face ID / Gerätecode.
@MainActor
final class FakeAuthenticator: BiometricAuthenticating {
    var available = true
    var results: [Bool] = []
    var prompts = 0

    func canAuthenticate() -> Bool { available }

    func authenticate(reason: String) async -> Bool {
        prompts += 1
        return results.isEmpty ? false : results.removeFirst()
    }
}

@MainActor
private func makeLock(enabled: Bool, auth: FakeAuthenticator = FakeAuthenticator()) -> (AppLock, UserDefaults) {
    let defaults = UserDefaults(suiteName: "AppLockTests-\(UUID().uuidString)")!
    defaults.set(enabled, forKey: AppLock.enabledKey)
    return (AppLock(defaults: defaults, authenticator: auth), defaults)
}

@MainActor @Test func locksOnBackgroundWhenEnabled() async {
    let auth = FakeAuthenticator()
    auth.results = [true]
    let (lock, _) = makeLock(enabled: true, auth: auth)
    await lock.unlock()                    // Kaltstart ist gesperrt → entsperren
    #expect(!lock.isLocked)

    lock.scenePhaseChanged(.inactive)      // z. B. Kontrollzentrum, Teilen-Menü
    #expect(!lock.isLocked)
    lock.scenePhaseChanged(.background)
    #expect(lock.isLocked)
}

@MainActor @Test func doesNotLockWhenDisabled() {
    let (lock, _) = makeLock(enabled: false)
    #expect(!lock.isEnabled)
    #expect(!lock.isLocked)
    lock.scenePhaseChanged(.background)
    #expect(!lock.isLocked)
}

@MainActor @Test func unlockFailureStaysLocked() async {
    let auth = FakeAuthenticator()
    auth.results = [false, true]
    let (lock, _) = makeLock(enabled: true, auth: auth)
    #expect(lock.isLocked)
    await lock.unlock()
    #expect(lock.isLocked)
    await lock.unlock()
    #expect(!lock.isLocked)
    #expect(auth.prompts == 2)
}

@MainActor @Test func enablingPersistsAndRequiresDeviceCode() async {
    let auth = FakeAuthenticator()
    auth.available = false
    let (lock, defaults) = makeLock(enabled: false, auth: auth)
    #expect(lock.setEnabled(true) == "Bitte zuerst in den Einstellungen einen Gerätecode festlegen.")
    #expect(!lock.isEnabled)

    auth.available = true
    #expect(lock.setEnabled(true) == nil)
    #expect(lock.isEnabled)
    #expect(!lock.isLocked)                // Einschalten sperrt nicht sofort
    #expect(defaults.bool(forKey: AppLock.enabledKey))

    lock.scenePhaseChanged(.background)
    #expect(lock.isLocked)
    #expect(lock.setEnabled(false) == nil)
    #expect(!lock.isLocked)
    #expect(!defaults.bool(forKey: AppLock.enabledKey))
}

/// Gerätecode nachträglich entfernt: nicht für immer aussperren.
@MainActor @Test func unlockWithoutDeviceCodeDisablesLock() async {
    let auth = FakeAuthenticator()
    let (lock, defaults) = makeLock(enabled: true, auth: auth)
    auth.available = false
    await lock.unlock()
    #expect(!lock.isLocked)
    #expect(!lock.isEnabled)
    #expect(!defaults.bool(forKey: AppLock.enabledKey))
    #expect(auth.prompts == 0)
}

@MainActor @Test func autoPromptOnlyOnceUntilNextBackground() async {
    let auth = FakeAuthenticator()
    auth.results = [false, false]
    let (lock, _) = makeLock(enabled: true, auth: auth)
    await lock.autoPromptIfNeeded()
    await lock.autoPromptIfNeeded()        // Face-ID-Dialog → inactive → active: kein zweiter Dialog
    #expect(auth.prompts == 1)
    lock.scenePhaseChanged(.background)
    await lock.autoPromptIfNeeded()
    #expect(auth.prompts == 2)
}
