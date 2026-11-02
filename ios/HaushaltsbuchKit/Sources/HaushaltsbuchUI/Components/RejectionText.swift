/// Ablehnungsgründe des Servers (`rejected[].reason`) für die Oberfläche. Der Rohgrund steht nur im
/// Log (SyncEngine), nie in der Anzeige.
enum RejectionText {
    static func german(_ reason: String?) -> String {
        switch reason {
        case "category_in_use": "Kategorie wird noch verwendet."
        case "unknown_user": "Person existiert nicht mehr."
        case "foreign_key_violation": "Verweis auf nicht vorhandene Daten."
        case "unique_violation": "Eintrag existiert bereits."
        case "invalid_value": "Ungültiger Wert."
        default: "Vom Server abgelehnt."
        }
    }
}
