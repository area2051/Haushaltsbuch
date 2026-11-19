import SwiftUI
import HaushaltsbuchCore

/// Auswahl des Rhythmus: Vorgaben (wöchentlich … jährlich) oder „Alle N Monate“ mit Stepper.
/// Mit `allowNone` steht „Nicht wiederholen“ (Wert `nil`) an erster Stelle (Schnellerfassung).
struct RhythmPickerView: View {
    @Binding var rhythm: Rhythm?
    var allowNone = false

    private enum Choice: Hashable { case none, preset(Rhythm), custom }

    /// Eigener Zustand: sonst würde „Alle 3 Monate“ beim Hochzählen zur Vorgabe „Vierteljährlich“
    /// springen und der Stepper verschwinden.
    @State private var customMode: Bool

    init(rhythm: Binding<Rhythm?>, allowNone: Bool = false) {
        _rhythm = rhythm
        self.allowNone = allowNone
        _customMode = State(initialValue: rhythm.wrappedValue.map { !$0.isPreset } ?? false)
    }

    private var choice: Binding<Choice> {
        Binding(
            get: {
                guard let r = rhythm else { return .none }
                return customMode ? .custom : .preset(r)
            },
            set: { new in
                switch new {
                case .none:
                    customMode = false
                    rhythm = nil
                case let .preset(r):
                    customMode = false
                    rhythm = r
                case .custom:
                    customMode = true
                    if rhythm == nil || rhythm?.isPreset == true { rhythm = Rhythm(frequency: .monthly, interval: 2) }
                }
            })
    }

    private var unit: String {
        switch rhythm?.frequency ?? .monthly {
        case .weekly: "Wochen"
        case .monthly: "Monate"
        case .yearly: "Jahre"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(allowNone ? "Wiederholen" : "Rhythmus", selection: choice) {
                if allowNone { Text("Nicht wiederholen").tag(Choice.none) }
                ForEach(Rhythm.presets, id: \.self) { Text($0.label).tag(Choice.preset($0)) }
                Text("Alle N Monate …").tag(Choice.custom)
            }
            .accessibilityIdentifier("rhythm.picker")
            if customMode, let current = rhythm {
                Stepper("Alle \(current.interval) \(unit)",
                        value: Binding(get: { current.interval },
                                       set: { rhythm = Rhythm(frequency: current.frequency, interval: $0) }),
                        in: 1...Rhythm.maxInterval)
                    .accessibilityIdentifier("rhythm.interval")
            }
        }
    }
}
