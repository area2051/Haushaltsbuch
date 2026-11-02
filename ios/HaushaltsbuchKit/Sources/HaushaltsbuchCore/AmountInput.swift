/// Ziffernblock-Eingabe: Ziffern werden von rechts eingeschoben (1,2,5,0 → 12,50 €). Max. 9 Ziffern.
public struct AmountInput: Equatable, Sendable {
    public static let maxCents = 999_999_999

    public private(set) var cents: Int = 0

    public init() {}

    /// Vorbelegung (z. B. beim Bearbeiten); wird auf 0…`maxCents` begrenzt.
    public init(cents: Int) { self.cents = min(max(cents, 0), Self.maxCents) }

    public mutating func append(digit: Int) {
        guard (0...9).contains(digit) else { return }
        let next = cents * 10 + digit
        guard next <= Self.maxCents else { return }
        cents = next
    }

    public mutating func deleteLast() { cents /= 10 }

    public mutating func clear() { cents = 0 }

    public var isValid: Bool { cents > 0 }

    public var display: String { Money.format(cents: cents) }
}
