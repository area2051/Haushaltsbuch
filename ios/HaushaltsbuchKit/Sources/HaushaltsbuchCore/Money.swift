import Foundation

public enum Money {
    private static let locale = Locale(identifier: "de_DE")

    /// „1.234,56 €“ (mit geschütztem Leerzeichen, wie vom Formatter geliefert).
    public static func format(cents: Int) -> String {
        (Decimal(cents) / 100).formatted(
            Decimal.FormatStyle.Currency(code: "EUR", locale: locale))
    }

    /// Einnahme „+12,50 €“, Ausgabe „−12,50 €“ (U+2212).
    public static func formatSigned(cents: Int, kind: Kind) -> String {
        let sign = kind == .income ? "+" : "\u{2212}"
        return sign + format(cents: cents)
    }
}
