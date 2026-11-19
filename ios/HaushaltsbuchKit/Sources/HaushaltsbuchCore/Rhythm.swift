/// Rhythmus einer wiederkehrenden Buchung: alle `interval` Wochen/Monate/Jahre
/// (z. B. monatlich × 3 = vierteljährlich). Gleiche Vorgaben und Texte wie die Web-App.
public struct Rhythm: Hashable, Sendable {
    public static let maxInterval = 24

    public var frequency: Frequency
    public var interval: Int

    public init(frequency: Frequency, interval: Int) {
        self.frequency = frequency
        self.interval = interval
    }

    /// Angebotene Rhythmen; alles andere ist „Alle N …“.
    public static let presets: [Rhythm] = [
        Rhythm(frequency: .weekly, interval: 1),
        Rhythm(frequency: .weekly, interval: 2),
        Rhythm(frequency: .monthly, interval: 1),
        Rhythm(frequency: .monthly, interval: 3),
        Rhythm(frequency: .monthly, interval: 6),
        Rhythm(frequency: .yearly, interval: 1),
    ]

    public var isPreset: Bool { Self.presets.contains(self) }

    /// Wie der Server: 1…24.
    public var isValid: Bool { (1...Self.maxInterval).contains(interval) }

    /// „Monatlich“, „Vierteljährlich“, „Alle 4 Monate“ …
    public var label: String {
        switch (frequency, interval) {
        case (.weekly, 1): "Wöchentlich"
        case (.weekly, 2): "Alle 2 Wochen"
        case (.monthly, 1): "Monatlich"
        case (.monthly, 3): "Vierteljährlich"
        case (.monthly, 6): "Halbjährlich"
        case (.yearly, 1): "Jährlich"
        case (.weekly, _): "Alle \(interval) Wochen"
        case (.monthly, _): "Alle \(interval) Monate"
        case (.yearly, _): "Alle \(interval) Jahre"
        }
    }
}
