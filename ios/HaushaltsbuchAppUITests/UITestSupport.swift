import XCTest

/// Fehlende Voraussetzung eines Live-Tests (z. B. keine gespeicherte Sitzung). Lässt den Test
/// fehlschlagen statt ihn still zu überspringen – sonst sähe ein nicht gelaufener Test wie ein
/// bestandener aus.
struct MissingPrecondition: Error, CustomStringConvertible {
    let description: String
}

/// Wartet auf `element`; fehlt es, schlägt der Test mit `message` fehl.
@MainActor
func requireExistence(_ element: XCUIElement, timeout: TimeInterval, _ message: String,
                      file: StaticString = #filePath, line: UInt = #line) throws {
    guard element.waitForExistence(timeout: timeout) else {
        XCTFail(message, file: file, line: line)
        throw MissingPrecondition(description: message)
    }
}

/// Ziffern der Tastatur (Cent) → Betragstext wie in den Zeilen, z. B. `1111` → `11,11`, `123456` → `1.234,56`.
func amountText(digits: String) -> String {
    let cents = Int(digits) ?? 0
    let f = NumberFormatter()
    f.locale = Locale(identifier: "de_DE")
    f.numberStyle = .decimal
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    return f.string(from: NSNumber(value: Double(cents) / 100)) ?? ""
}
