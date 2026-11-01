/// Art einer Buchung.
public enum Kind: String, Sendable, CaseIterable {
    case income, expense
}

/// Wiederholungsrhythmus (z. B. für Daueraufträge).
public enum Frequency: String, Sendable, CaseIterable {
    case weekly, monthly, yearly
}
