import Foundation
import SwiftData
import Testing
import HaushaltsbuchAPI
import HaushaltsbuchCore
@testable import HaushaltsbuchData

// MARK: Push / Antwort

@MainActor @Test func pushesDirtyAndClearsDirtyFromResponse() async throws {
    let f = try SyncFixture()
    let cat = try f.makeCategory()
    let tx = try f.addTx(category: cat.id)
    try f.repo.setBudget(categoryId: cat.id, monthlyLimitCents: 30000)
    let rule = try f.repo.saveRule(RuleDraft(amountCents: 5000, kind: .expense, categoryId: cat.id, note: nil,
                                             paidBy: f.user, frequency: .monthly, startDate: f.day, endDate: nil))

    await f.engine.syncNow()

    let req = try #require(f.transport.requests.first)
    #expect(f.transport.requests.count == 1)
    #expect(req.lastVersion == 0)
    #expect(req.changes.categories?.map(\.id) == [cat.id.uuidString.lowercased()])
    #expect(req.changes.transactions?.map(\.id) == [tx.id.uuidString.lowercased()])
    #expect(req.changes.recurringRules?.map(\.id) == [rule.id.uuidString.lowercased()])
    #expect(req.changes.budgets?.count == 1)
    let budget = try #require(try f.all(BudgetEntity.self).first)
    for e in [cat as any SyncTracked, tx, rule, budget] {
        #expect(!e.isDirty)
        #expect(e.version != nil)
    }
    #expect(f.repo.pendingChangesCount == 0)
    #expect(f.engine.status == .upToDate(SyncFixture.now))
}

@MainActor @Test func editDuringInFlightSyncStaysDirty() async throws {
    let f = try SyncFixture()
    let cat = try f.makeCategory()
    let tx = try f.addTx(category: cat.id, amount: 1250)
    let repo = f.repo, server = f.server
    f.transport.handle { req in
        // Nutzer ändert die Buchung, während der Push unterwegs ist.
        try repo.update(tx, amountCents: 999, kind: .expense, categoryId: cat.id,
                        day: CalendarDay(year: 2026, month: 11, day: 2)!, paidBy: tx.paidBy, note: nil)
        return server.handle(req)
    }

    await f.engine.syncNow()

    #expect(tx.isDirty)
    #expect(tx.amountCents == 999)
    #expect(tx.day == "2026-11-02")
    #expect(tx.version == nil)
    #expect(!cat.isDirty)

    // Der nächste Sync überträgt den neuen Stand.
    f.transport.handle { req in server.handle(req) }
    await f.engine.syncNow()
    #expect(f.transport.requests.last?.changes.transactions?.first?.amountCents == 999)
    #expect(!tx.isDirty)
    #expect(tx.amountCents == 999)
}

@MainActor @Test func appliesServerChangesAndUpsertsMembers() async throws {
    let f = try SyncFixture()
    let catId = UUID(), txId = UUID(), ruleId = UUID(), budgetId = UUID(), memberId = UUID()
    let local = TransactionEntity(amountCents: 100, kind: .expense, categoryId: catId, day: f.day,
                                  paidBy: f.user, note: nil, version: 3)
    f.context.insert(local)
    let member = MemberEntity(id: memberId, username: "bert", displayName: "Bert alt", isAdmin: false, version: 1)
    f.context.insert(member)
    try f.context.save()

    let l = { (u: UUID) in u.uuidString.lowercased() }
    f.server.extra = SyncChanges(
        budgets: [.init(categoryId: l(catId), deleted: false, id: l(budgetId), monthlyLimitCents: 40000, version: 12)],
        categories: [.init(archived: true, color: "#AABBCC", deleted: false, icon: "house", id: l(catId),
                           kind: .income, name: "Gehalt", sortOrder: 4, version: 10)],
        recurringRules: [.init(amountCents: 7000, categoryId: l(catId), deleted: false, endDate: "2027-12-31",
                               frequency: .yearly, id: l(ruleId), kind: .income, nextDueDate: "2027-01-15",
                               note: "Bonus", paidBy: l(memberId), startDate: "2026-01-15", version: 11)],
        transactions: [
            .init(amountCents: 250000, categoryId: l(catId), date: "2026-10-31", deleted: false, id: l(txId),
                  kind: .income, note: nil, paidBy: l(memberId), recurringRuleId: l(ruleId), version: 13),
            .init(amountCents: 4321, categoryId: l(catId), date: "2026-10-30", deleted: true, id: l(local.id),
                  kind: .expense, note: "geändert", paidBy: l(f.user), recurringRuleId: nil, version: 14),
        ],
        users: [
            .init(deleted: false, displayName: "Bert", id: l(memberId), isAdmin: true, username: "bert", version: 15),
            .init(deleted: true, displayName: "Carla", id: l(f.user), isAdmin: false, username: "carla", version: 16),
        ])

    await f.engine.syncNow()

    let cat = try #require(try f.all(CategoryEntity.self).first { $0.id == catId })
    #expect(cat.name == "Gehalt" && cat.icon == "house" && cat.color == "#AABBCC")
    #expect(cat.kind == "income" && cat.sortOrder == 4 && cat.archived && cat.version == 10 && !cat.isDirty)
    let rule = try #require(try f.all(RecurringRuleEntity.self).first)
    #expect(rule.id == ruleId && rule.amountCents == 7000 && rule.frequency == "yearly" && rule.kind == "income")
    #expect(rule.endDate == "2027-12-31" && rule.nextDueDate == "2027-01-15" && rule.startDate == "2026-01-15")
    #expect(rule.note == "Bonus" && rule.paidBy == memberId && rule.categoryId == catId && rule.version == 11)
    let budget = try #require(try f.all(BudgetEntity.self).first)
    #expect(budget.id == budgetId && budget.categoryId == catId && budget.monthlyLimitCents == 40000)
    let txs = try f.all(TransactionEntity.self)
    #expect(txs.count == 2)
    let generated = try #require(txs.first { $0.id == txId })
    #expect(generated.recurringRuleId == ruleId && generated.day == "2026-10-31" && generated.note == nil)
    #expect(generated.amountCents == 250000 && generated.paidBy == memberId && generated.version == 13)
    #expect(local.amountCents == 4321 && local.deleted && local.note == "geändert" && local.version == 14)
    #expect(local.day == "2026-10-30")

    let members = try f.all(MemberEntity.self)
    #expect(members.count == 2)
    #expect(member.displayName == "Bert" && member.isAdmin && member.version == 15)
    let carla = try #require(members.first { $0.id == f.user })
    #expect(carla.username == "carla" && carla.deleted)
    #expect(f.cursor.lastVersion == 16)
}

@MainActor @Test func uppercaseLocalIdMatchesLowercaseServerId() async throws {
    let f = try SyncFixture()
    let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
    let catId = UUID()
    let local = TransactionEntity(id: id, amountCents: 100, kind: .expense, categoryId: catId, day: f.day,
                                  paidBy: f.user, note: nil, version: 1)
    f.context.insert(local)
    try f.context.save()
    f.server.extra.transactions = [
        .init(amountCents: 777, categoryId: catId.uuidString.lowercased(), date: "2026-11-01", deleted: false,
              id: "6f9619ff-8b86-d011-b42d-00c04fc964ff", kind: .expense, note: nil,
              paidBy: f.user.uuidString.lowercased(), recurringRuleId: nil, version: 2),
    ]

    await f.engine.syncNow()

    #expect(try f.all(TransactionEntity.self).count == 1)
    #expect(local.amountCents == 777)
    #expect(local.version == 2)

    // Die Zuordnung muss den lokalen Datensatz treffen, nicht über „Anlegen“ (Upsert auf die
    // eindeutige ID) laufen: ein während des Requests bearbeiteter Datensatz bleibt sonst nicht geschützt.
    let repo = f.repo, server = f.server
    server.extra.transactions = []
    try repo.update(local, amountCents: 888, kind: .expense, categoryId: catId, day: f.day, paidBy: f.user, note: nil)
    f.transport.handle { req in
        #expect(req.changes.transactions?.first?.id == "6f9619ff-8b86-d011-b42d-00c04fc964ff")
        try repo.update(local, amountCents: 999, kind: .expense, categoryId: catId, day: f.day,
                        paidBy: f.user, note: nil)
        return server.handle(req)  // bestätigt den gesendeten Stand (888) mit kleingeschriebener ID
    }
    await f.engine.syncNow()

    #expect(try f.all(TransactionEntity.self).count == 1)
    #expect(local.isDirty)
    #expect(local.amountCents == 999)
}

@MainActor @Test func rejectedRecordIsMarkedAndNotResent() async throws {
    let f = try SyncFixture()
    let cat = try f.makeCategory()
    let tx = try f.addTx(category: cat.id, amount: 1250)
    let txId = tx.id.uuidString.lowercased()
    f.server.rejected = [
        .init(id: txId, reason: "unknown_user", table: "transactions"),
        // Ruling 3: passt zu keinem lokalen Datensatz → ignoriert.
        .init(id: UUID().uuidString.lowercased(), reason: "x", table: "budgets"),
        .init(id: nil, reason: "invalid record", table: "transactions"),
        .init(id: cat.id.uuidString.lowercased(), reason: "falsche Tabelle", table: "gibtsnicht"),
        .init(id: "keine-uuid", reason: "x", table: "categories"),
    ]

    await f.engine.syncNow()

    #expect(tx.rejectionReason == "unknown_user")
    #expect(!tx.isDirty)
    #expect(tx.amountCents == 1250)  // lokaler Stand bleibt zum Bearbeiten/Verwerfen
    #expect(cat.rejectionReason == nil)
    #expect(!cat.isDirty)
    #expect(f.engine.status == .upToDate(SyncFixture.now))

    f.server.rejected = []
    await f.engine.syncNow()
    let second = try #require(f.transport.requests.last)
    #expect((second.changes.transactions ?? []).isEmpty)
    #expect(tx.rejectionReason == "unknown_user")
}

@MainActor @Test func fullResyncRemovesUnknownCleanRecordsKeepsDirty() async throws {
    let f = try SyncFixture(lastVersion: 500)
    let catId = UUID()
    let l = { (u: UUID) in u.uuidString.lowercased() }
    let known = TransactionEntity(amountCents: 1, kind: .expense, categoryId: catId, day: f.day, paidBy: f.user,
                                  note: nil, version: 5)
    let unknown = TransactionEntity(amountCents: 2, kind: .expense, categoryId: catId, day: f.day, paidBy: f.user,
                                    note: nil, version: 6)
    let unknownCat = CategoryEntity(name: "Alt", icon: "x", color: "#000000", kind: .expense, sortOrder: 0, version: 7)
    let unknownBudget = BudgetEntity(categoryId: catId, monthlyLimitCents: 5, version: 8)
    let unknownRule = RecurringRuleEntity(amountCents: 3, kind: .expense, categoryId: catId, note: nil,
                                          paidBy: f.user, frequency: .weekly, startDate: f.day, endDate: nil,
                                          version: 9)
    let unknownMember = MemberEntity(id: UUID(), username: "weg", displayName: "Weg", isAdmin: false, version: 3)
    let keptMember = MemberEntity(id: f.user, username: "anna", displayName: "Anna", isAdmin: true, version: 4)
    for m in [known, unknown] as [any PersistentModel] { f.context.insert(m) }
    f.context.insert(unknownCat); f.context.insert(unknownBudget); f.context.insert(unknownRule)
    f.context.insert(unknownMember); f.context.insert(keptMember)
    try f.context.save()
    // Dirty, aber der Server meldet ihn (noch) nicht zurück → bleibt.
    let dirty = try f.addTx(category: catId, amount: 3)
    f.server.drop = [l(dirty.id)]
    // Abgelehnt (nie synchronisiert) → bleibt zum Bearbeiten.
    let rejected = try f.addTx(category: catId, amount: 4)
    f.server.rejected = [.init(id: l(rejected.id), reason: "unknown_user", table: "transactions")]
    f.server.fullResync = true
    f.server.currentVersion = 40
    f.server.extra.transactions = [
        .init(amountCents: 1, categoryId: l(catId), date: "2026-11-01", deleted: false, id: l(known.id),
              kind: .expense, note: nil, paidBy: l(f.user), recurringRuleId: nil, version: 20),
    ]
    f.server.extra.users = [.init(deleted: false, displayName: "Anna", id: l(f.user), isAdmin: true,
                                  username: "anna", version: 21)]

    await f.engine.syncNow()

    // Push lief zuerst normal.
    #expect(f.transport.requests.first?.lastVersion == 500)
    #expect(f.transport.requests.first?.changes.transactions?.count == 2)
    let txIds = Set(try f.all(TransactionEntity.self).map(\.id))
    #expect(txIds == [known.id, dirty.id, rejected.id])
    #expect(dirty.isDirty)
    #expect(rejected.rejectionReason == "unknown_user")
    #expect(try f.all(CategoryEntity.self).isEmpty)
    #expect(try f.all(BudgetEntity.self).isEmpty)
    #expect(try f.all(RecurringRuleEntity.self).isEmpty)
    #expect(try f.all(MemberEntity.self).map(\.id) == [f.user])
    #expect(f.cursor.lastVersion == 40)
}

@MainActor @Test func storesCurrentVersionAsCursor() async throws {
    let f = try SyncFixture(lastVersion: 7)
    f.server.currentVersion = 42

    await f.engine.syncNow()
    #expect(f.transport.requests.first?.lastVersion == 7)
    #expect(f.cursor.lastVersion == 42)

    await f.engine.syncNow()
    #expect(f.transport.requests.last?.lastVersion == 42)
}

@MainActor @Test func splitsPushIntoBatchesOf500() async throws {
    let f = try SyncFixture()
    let cat = try f.makeCategory()
    for i in 0..<1200 {
        let tx = TransactionEntity(amountCents: i + 1, kind: .expense, categoryId: cat.id, day: f.day,
                                   paidBy: f.user, note: nil)
        tx.markDirty()
        f.context.insert(tx)
    }
    try f.context.save()

    await f.engine.syncNow()

    let reqs = f.transport.requests
    let sizes = reqs.map { req in
        (req.changes.categories?.count ?? 0) + (req.changes.transactions?.count ?? 0)
            + (req.changes.budgets?.count ?? 0) + (req.changes.recurringRules?.count ?? 0)
    }
    #expect(sizes == [500, 500, 201])
    #expect(reqs.first?.changes.categories?.count == 1)  // Kategorien zuerst
    #expect(reqs.map(\.lastVersion) == [0, 500, 1000])
    let allIds = reqs.flatMap { $0.changes.transactions?.map(\.id) ?? [] }
    #expect(Set(allIds).count == 1200)
    #expect(f.repo.pendingChangesCount == 0)
    #expect(f.cursor.lastVersion == 1201)
}

// MARK: Fehler

@MainActor @Test func unreachableKeepsDataAndReportsPending() async throws {
    let f = try SyncFixture(lastVersion: 9)
    let cat = try f.makeCategory()
    let tx = try f.addTx(category: cat.id)
    f.transport.handle { _ in throw APIError(URLError(.notConnectedToInternet)) }

    await f.engine.syncNow()

    #expect(f.engine.status == .offline(pending: 2))
    #expect(cat.isDirty && tx.isDirty)
    #expect(tx.version == nil)
    #expect(f.cursor.lastVersion == 9)
    #expect(try f.all(TransactionEntity.self).count == 1)
}

@MainActor @Test func serverErrorReportsErrorAndUnauthorizedStops() async throws {
    let f = try SyncFixture()
    _ = try f.makeCategory()
    f.transport.handle { _ in throw APIError.server(code: "internal", message: "boom") }
    await f.engine.syncNow()
    #expect(f.engine.status == .error("Interner Serverfehler – bitte später erneut versuchen.", pending: 1))

    f.transport.handle { _ in throw APIError.unauthorized }
    await f.engine.syncNow()
    #expect(f.engine.status == .idle)
    #expect(f.transport.requests.count == 2)
}

// MARK: Rulings

@MainActor @Test func deletedBudgetsAreSentBeforeNewOnes() async throws {
    let f = try SyncFixture()
    let a = try f.makeCategory("A")
    let b = try f.makeCategory("B")
    // Je Kategorie: altes Budget gelöscht + neues angelegt, im selben Push. Die beiden Paare liegen
    // spiegelverkehrt (Einfüge- und ID-Reihenfolge), sodass jede „natürliche“ Abrufreihenfolge
    // (nach Einfügen oder ID, vorwärts oder rückwärts) bei einem der Paare das neue vor dem alten
    // liefern würde – nur explizites Sortieren besteht den Test.
    func budget(_ id: String, _ cat: UUID, version: Int?) -> BudgetEntity {
        let e = BudgetEntity(id: UUID(uuidString: id)!, categoryId: cat, monthlyLimitCents: 10000, version: version)
        f.context.insert(e)
        return e
    }
    let aFresh = budget("00000000-0000-0000-0000-000000000001", a.id, version: nil)
    let aOld = budget("FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF", a.id, version: 1)
    let bOld = budget("00000000-0000-0000-0000-000000000002", b.id, version: 2)
    let bFresh = budget("FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFE", b.id, version: nil)
    try f.context.save()
    for old in [aOld, bOld] { old.deleted = true }
    for e in [aFresh, aOld, bOld, bFresh] { e.markDirty() }
    try f.context.save()

    await f.engine.syncNow()

    let budgets = try #require(f.transport.requests.last?.changes.budgets)
    #expect(budgets.count == 4)
    #expect(budgets.map(\.deleted) == [true, true, false, false])
    #expect(Set(budgets.prefix(2).map(\.id)) == Set([aOld.id, bOld.id].map { $0.uuidString.lowercased() }))
}

@MainActor @Test func deletedCategoriesAreSentLast() async throws {
    let f = try SyncFixture(batchSize: 2)
    let doomed = try f.makeCategory("Weg")
    doomed.version = 1
    doomed.deleted = true
    doomed.markDirty()
    let kept = try f.makeCategory("Bleibt")
    let tx = try f.addTx(category: kept.id)

    await f.engine.syncNow()

    let order = f.transport.requests.flatMap { req in
        (req.changes.categories?.map(\.id) ?? []) + (req.changes.transactions?.map(\.id) ?? [])
    }
    #expect(order == [kept.id, tx.id, doomed.id].map { $0.uuidString.lowercased() })
}

@MainActor @Test func mappingSendsAllFieldsAndSkipsUnparseableServerIds() async throws {
    let f = try SyncFixture()
    let cat = try f.makeCategory()
    let ruleId = UUID()
    let tx = TransactionEntity(amountCents: 1999, kind: .income, categoryId: cat.id, day: f.day, paidBy: f.user,
                               note: nil, recurringRuleId: ruleId)
    tx.markDirty()
    f.context.insert(tx)
    let rule = try f.repo.saveRule(RuleDraft(amountCents: 5000, kind: .expense, categoryId: cat.id, note: "Miete",
                                             paidBy: f.user, frequency: .weekly, startDate: f.day,
                                             endDate: CalendarDay(year: 2027, month: 1, day: 31)))
    let l = { (u: UUID) in u.uuidString.lowercased() }
    let goodId = UUID()
    f.server.extra.transactions = [
        .init(amountCents: 1, categoryId: l(cat.id), date: "2026-11-01", deleted: false, id: "nope",
              kind: .expense, note: nil, paidBy: l(f.user), recurringRuleId: nil, version: 1),
        .init(amountCents: 1, categoryId: "kaputt", date: "2026-11-01", deleted: false, id: l(UUID()),
              kind: .expense, note: nil, paidBy: l(f.user), recurringRuleId: nil, version: 2),
        .init(amountCents: 5, categoryId: l(cat.id), date: "2026-11-01", deleted: false, id: l(goodId),
              kind: .expense, note: nil, paidBy: l(f.user), recurringRuleId: nil, version: 3),
    ]
    f.server.extra.users = [.init(deleted: false, displayName: "X", id: "kein-uuid", isAdmin: false,
                                  username: "x", version: 4)]

    await f.engine.syncNow()

    let req = try #require(f.transport.requests.first)
    let c = try #require(req.changes.categories?.first)
    #expect(c.id == l(cat.id) && c.name == "Essen" && c.icon == "cart" && c.color == "#112233")
    #expect(c.kind == .expense && c.sortOrder == 0 && !c.archived && !c.deleted)
    let t = try #require(req.changes.transactions?.first)
    #expect(t.id == l(tx.id) && t.amountCents == 1999 && t.kind == .income && t.categoryId == l(cat.id))
    #expect(t.date == "2026-11-01" && t.paidBy == l(f.user) && t.note == nil && t.recurringRuleId == l(ruleId))
    let r = try #require(req.changes.recurringRules?.first)
    #expect(r.id == l(rule.id) && r.frequency == .weekly && r.startDate == "2026-11-01" && r.endDate == "2027-01-31")
    #expect(r.note == "Miete" && r.paidBy == l(f.user) && r.amountCents == 5000)

    let ids = Set(try f.all(TransactionEntity.self).map(\.id))
    #expect(ids == [tx.id, goodId])
    #expect(try f.all(MemberEntity.self).isEmpty)
    #expect(f.engine.status == .upToDate(SyncFixture.now))
}

@MainActor @Test func cancellationErrorRestoresPreviousStatus() async throws {
    let f = try SyncFixture()
    await f.engine.syncNow()
    #expect(f.engine.status == .upToDate(SyncFixture.now))
    _ = try f.makeCategory()

    f.transport.handle { _ in throw CancellationError() }
    await f.engine.syncNow()
    #expect(f.engine.status == .upToDate(SyncFixture.now))

    f.transport.handle { _ in throw APIError(URLError(.cancelled)) }
    await f.engine.syncNow()
    #expect(f.engine.status == .upToDate(SyncFixture.now))
}

@MainActor @Test func cancellingSyncTaskStopsQuietly() async throws {
    let f = try SyncFixture()
    let cat = try f.makeCategory()
    let latch = Latch()
    let server = f.server
    f.transport.handle { req in
        try await latch.wait()
        return server.handle(req)
    }

    let task = Task { await f.engine.syncNow() }
    await waitUntil { latch.arrivals == 1 }
    #expect(f.engine.status == .syncing)
    task.cancel()
    await task.value

    #expect(f.engine.status == .idle)
    #expect(cat.isDirty)
    #expect(f.cursor.lastVersion == 0)
}

@MainActor @Test func concurrentSyncNowCoalesces() async throws {
    let f = try SyncFixture()
    _ = try f.makeCategory()
    let latch = Latch()
    let server = f.server
    f.transport.handle { req in
        try await latch.wait()
        return server.handle(req)
    }

    let first = Task { await f.engine.syncNow() }
    await waitUntil { latch.arrivals == 1 }
    let second = Task { await f.engine.syncNow() }
    let third = Task { await f.engine.syncNow() }
    for _ in 0..<20 { await Task.yield() }
    #expect(f.transport.requests.count == 1)
    latch.open()
    await first.value
    await second.value
    await third.value

    #expect(f.transport.requests.count == 2)  // ein Durchlauf + genau ein Nachlauf
    #expect(f.transport.maxInFlight == 1)
    #expect(f.engine.status == .upToDate(SyncFixture.now))
}

@Test func apiErrorMapsCancellation() {
    #expect(APIError(CancellationError()) == .cancelled)
    #expect(APIError(URLError(.cancelled)) == .cancelled)
}

@Test func cursorStoreKeyContainsServerAndUser() {
    let defaults = UserDefaults(suiteName: "SyncCursor-\(UUID().uuidString)")!
    let user = UUID()
    var store = UserDefaultsCursorStore(serverURL: URL(string: "http://nas.local:3000")!, userId: user,
                                        defaults: defaults)
    #expect(store.key.contains("http://nas.local:3000"))
    #expect(store.key.contains(user.uuidString.lowercased()))
    #expect(store.lastVersion == 0)
    store.lastVersion = 17
    #expect(UserDefaultsCursorStore(key: store.key, defaults: defaults).lastVersion == 17)
}
