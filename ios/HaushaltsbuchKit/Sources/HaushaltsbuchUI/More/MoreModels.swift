import Foundation
import HaushaltsbuchCore
import HaushaltsbuchData

// MARK: Export

struct ExportRange: Equatable, Sendable {
    var from: CalendarDay
    var to: CalendarDay
}

/// Zeitraum des CSV-Exports.
enum ExportPeriod: String, CaseIterable, Identifiable, Sendable {
    case thisMonth, lastMonth, thisYear, custom

    var id: Self { self }

    var title: String {
        switch self {
        case .thisMonth: "Dieser Monat"
        case .lastMonth: "Letzter Monat"
        case .thisYear: "Dieses Jahr"
        case .custom: "Frei"
        }
    }

    /// `nil` bei freiem Zeitraum mit Ende vor Start.
    func range(today: CalendarDay, customFrom: CalendarDay? = nil, customTo: CalendarDay? = nil) -> ExportRange? {
        switch self {
        case .thisMonth:
            return Self.month(today.monthKey)
        case .lastMonth:
            return Self.month(today.monthKey.adding(months: -1))
        case .thisYear:
            return ExportRange(from: CalendarDay(year: today.year, month: 1, day: 1)!,
                               to: CalendarDay(year: today.year, month: 12, day: 31)!)
        case .custom:
            let from = customFrom ?? today, to = customTo ?? today
            return from <= to ? ExportRange(from: from, to: to) : nil
        }
    }

    private static func month(_ m: MonthKey) -> ExportRange {
        let first = CalendarDay(year: m.year, month: m.month, day: 1)!
        let next = m.adding(months: 1)
        let last = CalendarDay(year: next.year, month: next.month, day: 1)!.adding(days: -1)
        return ExportRange(from: first, to: last)
    }
}

enum ExportModel {
    /// Schreibt die CSV in eine temporäre Datei (`CSVExport.fileName`) und liefert deren URL.
    /// `txs` sind bereits ohne gelöschte Buchungen.
    static func writeFile(txs: [TxValue], categories: [CategoryValue], members: [UUID: String],
                          range: ExportRange, directory: URL = ExportModel.directory) throws -> URL {
        let data = CSVExport.make(txs, tree: CategoryTree(categories), members: members, from: range.from, to: range.to)
        // Nur die aktuelle Datei behalten (keine alten Exporte im tmp-Ordner).
        removeTemporaryFiles(in: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dir = directory
        let url = dir.appendingPathComponent(CSVExport.fileName(from: range.from, to: range.to))
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Ordner der temporären Exportdateien.
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
    }

    /// Löscht alle temporären Exportdateien (vor jedem Export und beim Abmelden).
    static func removeTemporaryFiles(in directory: URL = ExportModel.directory) {
        try? FileManager.default.removeItem(at: directory)
    }

    static func rowCount(txs: [TxValue], range: ExportRange) -> Int {
        txs.filter { $0.day >= range.from && $0.day <= range.to }.count
    }
}

// MARK: Kategorien

enum CategoryForm {
    static let maxNameLength = 40

    /// Feste Auswahl an SF Symbols.
    static let symbols = [
        "cart", "basket", "fork.knife", "cup.and.saucer", "house", "bolt", "drop", "flame",
        "car", "fuelpump", "bus", "tram", "bicycle", "airplane", "cross.case", "pills",
        "heart", "figure.run", "tshirt", "scissors", "gift", "gamecontroller", "film", "music.note",
        "book", "graduationcap", "pawprint", "leaf", "wifi", "iphone", "wrench.and.screwdriver",
        "banknote", "creditcard", "eurosign", "chart.line.uptrend.xyaxis", "building.columns",
        "briefcase", "person.2", "ellipsis.circle",
    ]

    /// Feste Palette (12 Farben, Material-Töne).
    static let palette = [
        "#F44336", "#E91E63", "#9C27B0", "#673AB7", "#3F51B5", "#2196F3",
        "#00BCD4", "#009688", "#4CAF50", "#CDDC39", "#FF9800", "#795548",
    ]

    static func validationMessage(name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Bitte einen Namen eingeben." }
        if trimmed.count > maxNameLength { return "Der Name darf höchstens 40 Zeichen lang sein." }
        return nil
    }

    static func removalMessage(archived: Bool) -> String {
        archived ? "Kategorie archiviert – sie wird in alten Buchungen weiter angezeigt." : "Kategorie gelöscht."
    }

    /// Hauptkategorie mit (nicht gelöschten) Unterkategorien: Entfernen gesperrt (Server: `category_has_children`).
    static let removalBlockedText = "Erst Unterkategorien entfernen"

    /// `all` ohne gelöschte Kategorien.
    static func hasChildren(_ id: UUID, in all: [CategoryValue]) -> Bool {
        all.contains { $0.parentId == id }
    }

    /// Mögliche Hauptkategorien für „Gehört zu“: aktive Hauptkategorien der Art außer `c`; keine, wenn
    /// `c` selbst Unterkategorien hat (nur eine Ebene). `all` ohne gelöschte Kategorien.
    static func parentOptions(for c: CategoryValue?, all: [CategoryValue], kind: Kind) -> [CategoryValue] {
        if let c, hasChildren(c.id, in: all) { return [] }
        return all.filter { $0.parentId == nil && $0.kind == kind && !$0.archived && $0.id != c?.id }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    /// Hinweis vor dem Speichern, wenn `c` mit Budget Unterkategorie von `parent` wird (der Server hängt
    /// das Budget um oder löscht es). `budgets` nur nicht gelöschte.
    static func budgetHint(for c: CategoryValue, parent: CategoryValue?, budgets: [BudgetValue]) -> String? {
        guard let parent, c.parentId != parent.id, budgets.contains(where: { $0.categoryId == c.id }) else { return nil }
        return budgets.contains { $0.categoryId == parent.id }
            ? "Das Budget dieser Kategorie wird gelöscht, weil \(parent.name) schon eins hat."
            : "Das Budget geht auf \(parent.name) über."
    }
}

/// Liste der Kategorienverwaltung: Unterkategorien eingerückt unter ihrer Hauptkategorie.
enum CategoryList {
    struct Row: Equatable, Identifiable {
        var category: CategoryValue
        var isChild: Bool
        var id: UUID { category.id }
    }

    /// Aktive Hauptkategorien der Art (Reihenfolge), je gefolgt von ihren aktiven Unterkategorien.
    static func activeRows(_ all: [CategoryValue], kind: Kind) -> [Row] {
        let tree = CategoryTree(all)
        return mains(tree, kind: kind).flatMap { main in
            [Row(category: main, isChild: false)]
                + tree.childrenOf(main.id).filter { !$0.archived }.map { Row(category: $0, isChild: true) }
        }
    }

    /// Archivierte der Art – auch Unterkategorien einer archivierten Hauptkategorie –, nach Label.
    static func archived(_ all: [CategoryValue], kind: Kind) -> [CategoryValue] {
        let tree = CategoryTree(all)
        return all.filter { $0.kind == kind && !tree.isSelectable($0) }
            .sorted { tree.label($0.id).localizedStandardCompare(tree.label($1.id)) == .orderedAscending }
    }

    /// Neue Reihenfolge (IDs) nach `onMove`: eine Hauptkategorie wandert mit ihren Unterkategorien; eine
    /// Unterkategorie nur innerhalb ihrer Geschwister (sonst `nil`).
    static func reordered(_ rows: [Row], from source: IndexSet, to destination: Int) -> [UUID]? {
        guard source.count == 1, let index = source.first, rows.indices.contains(index) else { return nil }
        let moved = rows[index]
        if moved.isChild {
            let siblings = rows.indices.filter { rows[$0].isChild && rows[$0].category.parentId == moved.category.parentId }
            guard let first = siblings.first, let last = siblings.last, (first...last + 1).contains(destination)
            else { return nil }
            var result = rows
            result.move(fromOffsets: source, toOffset: destination)
            return result.map(\.id)
        }
        var mains = rows.filter { !$0.isChild }
        let from = mains.firstIndex { $0.id == moved.id }!
        mains.move(fromOffsets: [from], toOffset: rows[..<destination].filter { !$0.isChild }.count)
        return mains.flatMap { main in
            [main.id] + rows.filter { $0.isChild && $0.category.parentId == main.id }.map(\.id)
        }
    }

    private static func mains(_ tree: CategoryTree, kind: Kind) -> [CategoryValue] {
        tree.byId.values.filter { $0.kind == kind && !$0.archived && tree.rootOf($0.id) == $0.id }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }
}

// MARK: Wiederkehrende

enum RuleFormat {
    static func date(_ d: CalendarDay) -> String {
        String(format: "%02d.%02d.%04d", d.day, d.month, d.year)
    }

    static func nextDue(_ d: CalendarDay?) -> String {
        "Nächster Termin: " + (d.map(date) ?? "wird vom Server berechnet")
    }
}

// MARK: Mitglieder

enum MembersModel {
    static let offlineMessage = "Nur mit Verbindung zum Server möglich"

    static func message(for error: any Error) -> String {
        let api = APIError(error)
        switch api {
        case .unreachable:
            return offlineMessage
        case let .server(code, _):
            switch code {
            case "username_taken": return "Benutzername ist bereits vergeben."
            case "last_admin": return "Der letzte Admin kann nicht entfernt oder herabgestuft werden."
            case "cannot_delete_self": return "Du kannst dich nicht selbst entfernen."
            default: return api.germanMessage
            }
        default:
            return api.germanMessage
        }
    }

    /// Neues Mitglied (Regeln wie der Server: Benutzername 3–32 `[a-z0-9._-]`, Passwort ≥ 8).
    static func validationMessage(username: String, displayName: String, password: String) -> String? {
        let validUsername = (3...32).contains(username.count)
            && username.unicodeScalars.allSatisfy { "abcdefghijklmnopqrstuvwxyz0123456789._-".unicodeScalars.contains($0) }
        if !validUsername { return "Benutzername: 3–32 Zeichen, nur a–z, 0–9, Punkt, Unterstrich, Bindestrich." }
        return validationMessage(displayName: displayName, password: password, passwordRequired: true)
    }

    /// Bearbeiten: leeres Passwort = nicht zurücksetzen.
    static func validationMessage(displayName: String, password: String, passwordRequired: Bool = false) -> String? {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Bitte einen Anzeigenamen eingeben." }
        if name.count > 50 { return "Der Anzeigename darf höchstens 50 Zeichen lang sein." }
        if (passwordRequired || !password.isEmpty) && password.count < 8 {
            return "Das Passwort muss mindestens 8 Zeichen haben."
        }
        return nil
    }
}

// MARK: Server & Sync

enum ServerStatusText {
    static func status(_ s: SyncStatus) -> String {
        switch s {
        case .idle: "Noch nicht synchronisiert"
        case .syncing: "Synchronisiert …"
        case .offline: "Server nicht erreichbar"
        case let .error(message, _): "Fehler: \(message)"
        case let .upToDate(date): "Aktuell (zuletzt \(date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "de_DE")))))"
        }
    }

    static func pending(_ n: Int) -> String {
        switch n {
        case 0: "Keine ausstehenden Änderungen"
        case 1: "1 ausstehende Änderung"
        default: "\(n) ausstehende Änderungen"
        }
    }

    /// Text unter der Rückfrage (ohne Annahme über die Ursache); `rejected` = vom Server abgelehnte.
    static func logoutDetail(_ n: Int, rejected r: Int = 0) -> String {
        var parts: [String] = []
        if n > 0 {
            parts.append(n == 1 ? "1 Änderung konnte nicht übertragen werden und geht beim Abmelden verloren."
                : "\(n) Änderungen konnten nicht übertragen werden und gehen beim Abmelden verloren.")
        }
        if r > 0 {
            let also = n > 0 ? "ebenfalls " : ""
            parts.append(r == 1 ? "1 vom Server abgelehnte Änderung geht beim Abmelden \(also)verloren."
                : "\(r) vom Server abgelehnte Änderungen gehen beim Abmelden \(also)verloren.")
        }
        return parts.joined(separator: " ")
    }

    static func logoutWarning(_ n: Int, rejected r: Int = 0) -> String {
        if r == 0 {
            return n == 1 ? "1 ungesendete Änderung geht verloren" : "\(n) ungesendete Änderungen gehen verloren"
        }
        let total = n + r
        return total == 1 ? "1 Änderung geht verloren" : "\(total) Änderungen gehen verloren"
    }
}
