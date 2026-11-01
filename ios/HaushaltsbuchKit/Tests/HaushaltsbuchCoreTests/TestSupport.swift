import Foundation

extension String {
    /// Normalisiert geschützte Leerzeichen (NBSP, schmales NBSP) zu normalen Leerzeichen.
    var normalizedSpaces: String {
        replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
    }
}
