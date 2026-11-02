import SwiftUI

/// Notizen: der Server lässt höchstens 200 Zeichen zu (zod `max(200)` zählt UTF-16-Einheiten).
enum NoteLimit {
    static let maxLength = 200

    /// Schneidet an Zeichengrenzen so ab, dass höchstens `maxLength` UTF-16-Einheiten bleiben.
    static func clamp(_ text: String) -> String {
        guard text.utf16.count > maxLength else { return text }
        var result = ""
        var units = 0
        for character in text {
            let n = character.utf16.count
            if units + n > maxLength { break }
            result.append(character)
            units += n
        }
        return result
    }

    /// Getrimmt und begrenzt; leer → `nil`.
    static func normalized(_ text: String) -> String? {
        let trimmed = clamp(text.trimmingCharacters(in: .whitespacesAndNewlines))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension View {
    /// Begrenzt eine Notiz-Eingabe während des Tippens auf `NoteLimit.maxLength`.
    func limitNote(_ text: Binding<String>) -> some View {
        onChange(of: text.wrappedValue) { _, new in
            let clamped = NoteLimit.clamp(new)
            if clamped != new { text.wrappedValue = clamped }
        }
    }
}
