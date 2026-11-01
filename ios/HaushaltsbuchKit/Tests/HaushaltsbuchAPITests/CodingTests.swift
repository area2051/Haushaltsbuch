import Foundation
import Testing
import HaushaltsbuchAPI

/// Minimal, schema-gültige SyncResponse (lowercase UUIDs, nullable Felder als null).
private let syncResponseJSON = """
{
  "currentVersion": 42,
  "fullResync": false,
  "changes": {
    "categories": [
      {
        "id": "0b6f6d1e-4a0e-4c47-9d2a-1f3c5e7a9b01",
        "version": 3,
        "deleted": false,
        "name": "Lebensmittel",
        "icon": "cart",
        "color": "#33AA55",
        "kind": "expense",
        "sortOrder": 1,
        "archived": false
      }
    ],
    "transactions": [
      {
        "id": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
        "version": 41,
        "deleted": false,
        "amountCents": 1299,
        "kind": "expense",
        "categoryId": "0b6f6d1e-4a0e-4c47-9d2a-1f3c5e7a9b01",
        "date": "2026-10-31",
        "note": null,
        "paidBy": "a3bb189e-8bf9-3888-9912-ace4e6543002",
        "recurringRuleId": null
      }
    ],
    "budgets": [
      {
        "id": "e4eaaaf2-d142-11e1-b3e4-080027620cdd",
        "version": 5,
        "deleted": false,
        "categoryId": "0b6f6d1e-4a0e-4c47-9d2a-1f3c5e7a9b01",
        "monthlyLimitCents": 40000
      }
    ],
    "recurringRules": [
      {
        "id": "9f8e7d6c-5b4a-4321-8fed-cba987654321",
        "version": 7,
        "deleted": false,
        "amountCents": 89000,
        "kind": "expense",
        "categoryId": "0b6f6d1e-4a0e-4c47-9d2a-1f3c5e7a9b01",
        "note": null,
        "paidBy": "a3bb189e-8bf9-3888-9912-ace4e6543002",
        "frequency": "monthly",
        "startDate": "2026-01-01",
        "endDate": null,
        "nextDueDate": "2026-11-01"
      }
    ],
    "users": [
      {
        "id": "a3bb189e-8bf9-3888-9912-ace4e6543002",
        "username": "anna",
        "displayName": "Anna",
        "isAdmin": true,
        "version": 1,
        "deleted": false
      }
    ]
  },
  "rejected": [
    { "table": "transactions", "id": null, "reason": "invalid_record" }
  ]
}
"""

/// Gleiche Antwort, aber mit unbekannten Zusatzfeldern auf mehreren Ebenen.
private let syncResponseWithUnknownFieldsJSON = syncResponseJSON
    .replacingOccurrences(of: "\"currentVersion\": 42,", with: "\"currentVersion\": 42, \"futureField\": {\"a\": 1},")
    .replacingOccurrences(of: "\"date\": \"2026-10-31\",", with: "\"date\": \"2026-10-31\", \"futureField\": \"x\",")

private func decodeSyncResponse(_ json: String) throws -> Components.Schemas.SyncResponse {
    try JSONDecoder().decode(Components.Schemas.SyncResponse.self, from: Data(json.utf8))
}

private func encodeToObject<T: Encodable>(_ value: T) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

/// Der generierte Encoder (synthetisiertes Codable) lässt `nil` weg, statt `null` zu senden.
/// Der Server wertet einen fehlenden Schlüssel bei `note`, `recurringRuleId` und `endDate` als `null`
/// (`server/src/sync/schemas.ts`, `missingAsNull`). Akzeptiert wird daher „fehlt oder null“.
private func isMissingOrNull(_ object: [String: Any], _ key: String) -> Bool {
    guard let value = object[key] else { return true }
    return value is NSNull
}

@Test func decodesSyncResponseWithLowercaseIdsAndNulls() throws {
    let response = try decodeSyncResponse(syncResponseJSON)

    #expect(response.currentVersion == 42)
    #expect(response.fullResync == false)
    let tx = try #require(response.changes.transactions.first)
    #expect(tx.id == "7c9e6679-7425-40de-944b-e07fc1f90ae7")
    #expect(UUID(uuidString: tx.id) != nil)
    #expect(tx.amountCents == 1299)
    #expect(tx.kind == .expense)
    #expect(tx.date == "2026-10-31")
    #expect(tx.note == nil)
    #expect(tx.recurringRuleId == nil)

    let rule = try #require(response.changes.recurringRules.first)
    #expect(rule.note == nil)
    #expect(rule.endDate == nil)
    #expect(rule.frequency == .monthly)
    #expect(rule.nextDueDate == "2026-11-01")

    #expect(response.changes.categories.first?.kind == .expense)
    #expect(response.changes.budgets.first?.monthlyLimitCents == 40000)
    #expect(response.changes.users.first?.username == "anna")
    #expect(response.rejected.first?.id == nil)
    #expect(response.rejected.first?.reason == "invalid_record")
}

@Test func decodesNonNullNullableFields() throws {
    let json = syncResponseJSON
        .replacingOccurrences(of: "\"note\": null,\n        \"paidBy\": \"a3bb189e-8bf9-3888-9912-ace4e6543002\",\n        \"recurringRuleId\": null",
                              with: "\"note\": \"Wocheneinkauf\",\n        \"paidBy\": \"a3bb189e-8bf9-3888-9912-ace4e6543002\",\n        \"recurringRuleId\": \"9f8e7d6c-5b4a-4321-8fed-cba987654321\"")
        .replacingOccurrences(of: "\"endDate\": null", with: "\"endDate\": \"2026-12-31\"")
    let response = try decodeSyncResponse(json)
    let tx = try #require(response.changes.transactions.first)
    #expect(tx.note == "Wocheneinkauf")
    #expect(tx.recurringRuleId == "9f8e7d6c-5b4a-4321-8fed-cba987654321")
    #expect(response.changes.recurringRules.first?.endDate == "2026-12-31")
}

@Test func ignoresUnknownResponseFields() throws {
    let response = try decodeSyncResponse(syncResponseWithUnknownFieldsJSON)
    #expect(response.currentVersion == 42)
    #expect(response.changes.transactions.first?.amountCents == 1299)
}

@Test func encodesNilOptionalsAsExplicitNull() throws {
    let record = Components.Schemas.TransactionRecord(
        amountCents: 1299,
        categoryId: "0b6f6d1e-4a0e-4c47-9d2a-1f3c5e7a9b01",
        date: "2026-10-31",
        deleted: false,
        id: "7c9e6679-7425-40de-944b-e07fc1f90ae7",
        kind: .expense,
        note: nil,
        paidBy: "a3bb189e-8bf9-3888-9912-ace4e6543002",
        recurringRuleId: nil
    )
    let object = try encodeToObject(record)

    #expect(isMissingOrNull(object, "note"))
    #expect(isMissingOrNull(object, "recurringRuleId"))
    #expect(object["amountCents"] as? Int == 1299)
    #expect(object["date"] as? String == "2026-10-31")
}

@Test func encodesRecurringRuleNilEndDateAsNull() throws {
    let rule = Components.Schemas.RecurringRuleRecord(
        amountCents: 89000,
        categoryId: "0b6f6d1e-4a0e-4c47-9d2a-1f3c5e7a9b01",
        deleted: false,
        endDate: nil,
        frequency: .monthly,
        id: "9f8e7d6c-5b4a-4321-8fed-cba987654321",
        kind: .expense,
        note: nil,
        paidBy: "a3bb189e-8bf9-3888-9912-ace4e6543002",
        startDate: "2026-01-01"
    )
    let object = try encodeToObject(rule)

    #expect(isMissingOrNull(object, "endDate"))
    #expect(isMissingOrNull(object, "note"))
    #expect(object["frequency"] as? String == "monthly")
    #expect(object["startDate"] as? String == "2026-01-01")
}

@Test func encodesNonNilOptionalsAsValues() throws {
    var rule = Components.Schemas.RecurringRuleRecord(
        amountCents: 89000,
        categoryId: "0b6f6d1e-4a0e-4c47-9d2a-1f3c5e7a9b01",
        deleted: false,
        frequency: .yearly,
        id: "9f8e7d6c-5b4a-4321-8fed-cba987654321",
        kind: .income,
        paidBy: "a3bb189e-8bf9-3888-9912-ace4e6543002",
        startDate: "2026-01-01"
    )
    rule.note = "Gehalt"
    rule.endDate = "2026-12-31"
    let object = try encodeToObject(rule)
    #expect(object["note"] as? String == "Gehalt")
    #expect(object["endDate"] as? String == "2026-12-31")

    let decoded = try JSONDecoder().decode(Components.Schemas.RecurringRuleRecord.self, from: JSONEncoder().encode(rule))
    #expect(decoded == rule)
}

@Test func makeClientBuildsClientForServerURL() throws {
    let url = try #require(URL(string: "http://localhost:3000"))
    _ = makeClient(serverURL: url, middlewares: [])
}
