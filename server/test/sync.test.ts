import { randomUUID } from 'node:crypto'
import { eq, sql } from 'drizzle-orm'
import { afterEach, describe, expect, test } from 'vitest'
import { budgets, categories, recurringRules, transactions, users } from '../src/db/schema.js'
import { createTestApp, login, setupAdmin } from './helpers.js'

type TestApp = Awaited<ReturnType<typeof createTestApp>>
type Row = Record<string, unknown> & { id: string; version: number }
type SyncResult = {
  currentVersion: number
  fullResync: boolean
  changes: { categories: Row[]; transactions: Row[]; budgets: Row[]; recurringRules: Row[]; users: Row[] }
  rejected: { table: string; id: string | null; reason: string }[]
}

const auth = (token: string) => ({ authorization: `Bearer ${token}` })

describe('POST /sync', () => {
  let t: TestApp
  afterEach(async () => {
    await t?.close()
  })

  // Default test clock: 2026-01-15T12:00:00Z → today in Europe/Berlin = 2026-01-15.
  async function start(opts: Parameters<typeof createTestApp>[0] = {}) {
    t = await createTestApp(opts)
    const admin = await setupAdmin(t.app)
    const { accessToken } = await login(t.app, 'admin', 'geheim123')
    return { admin, token: accessToken }
  }

  // Categories without subcategories (deleting a parent that has children is rejected).
  const leafCategories = <C extends Row>(cats: C[]) => cats.filter((c) => !cats.some((o) => o.parentId === c.id))

  async function addMember(adminToken: string, username = 'anna') {
    const res = await t.app.inject({
      method: 'POST',
      url: '/users',
      headers: auth(adminToken),
      payload: { username, displayName: 'Anna', password: 'passwort1' },
    })
    expect(res.statusCode).toBe(201)
    const { accessToken } = await login(t.app, username, 'passwort1')
    return { user: res.json() as { id: string }, token: accessToken }
  }

  async function sync(token: string, lastVersion: number, changes: Record<string, unknown[]> = {}) {
    const res = await t.app.inject({
      method: 'POST',
      url: '/sync',
      headers: auth(token),
      payload: { lastVersion, changes },
    })
    expect(res.statusCode, res.body).toBe(200)
    return res.json() as SyncResult
  }

  async function categoryId(token: string, kind: 'expense' | 'income' = 'expense') {
    const r = await sync(token, 0)
    return r.changes.categories.find((c) => c.kind === kind)!.id
  }

  function txn(over: Record<string, unknown> & { categoryId: string; paidBy: string }) {
    return {
      id: randomUUID(),
      deleted: false,
      amountCents: 1250,
      kind: 'expense' as 'expense' | 'income',
      date: '2026-01-14',
      note: null,
      recurringRuleId: null,
      ...over,
    }
  }

  function rule(over: Record<string, unknown> & { categoryId: string; paidBy: string }) {
    return {
      id: randomUUID(),
      deleted: false,
      amountCents: 80000,
      kind: 'expense',
      note: 'Miete',
      frequency: 'monthly',
      startDate: '2026-02-01',
      endDate: null,
      ...over,
    }
  }

  test('initial sync returns default categories and users', async () => {
    const { admin, token } = await start()
    const r = await sync(token, 0)
    expect(r.fullResync).toBe(false)
    expect(r.rejected).toEqual([])
    expect(r.changes.categories).toHaveLength(48)
    expect(r.changes.users).toHaveLength(1)
    expect(r.changes.users[0]).toMatchObject({ ...admin, deleted: false })
    expect(r.changes.users[0]).not.toHaveProperty('passwordHash')
    expect(r.changes.transactions).toEqual([])
    expect(r.changes.budgets).toEqual([])
    expect(r.changes.recurringRules).toEqual([])
    expect(r.currentVersion).toBeGreaterThan(0)
    const versions = [...r.changes.categories, ...r.changes.users].map((x) => x.version)
    expect(r.currentVersion).toBe(Math.max(...versions))
  })

  test('pushed transaction is returned to another user', async () => {
    const { admin, token } = await start()
    const b = await addMember(token)
    const cat = await categoryId(token)
    const record = txn({ categoryId: cat, paidBy: admin.id, note: 'Einkauf' })
    const pushed = await sync(token, 0, { transactions: [record] })
    expect(pushed.rejected).toEqual([])
    expect(pushed.changes.transactions).toEqual([{ ...record, version: expect.any(Number) }])

    const r = await sync(b.token, 0)
    expect(r.changes.transactions).toHaveLength(1)
    expect(r.changes.transactions[0]).toMatchObject({ id: record.id, paidBy: admin.id, note: 'Einkauf' })
    expect(r.changes.users.map((u) => u.id).sort()).toEqual([admin.id, b.user.id].sort())
  })

  test('only changes after lastVersion are returned', async () => {
    const { admin, token } = await start()
    const first = await sync(token, 0)
    const cat = leafCategories(first.changes.categories)[0]!.id
    const record = txn({ categoryId: cat, paidBy: admin.id })
    const pushed = await sync(token, first.currentVersion, { transactions: [record] })
    expect(pushed.changes.categories).toEqual([])
    expect(pushed.changes.users).toEqual([])
    expect(pushed.changes.transactions.map((x) => x.id)).toEqual([record.id])
    expect(pushed.currentVersion).toBeGreaterThan(first.currentVersion)

    const again = await sync(token, pushed.currentVersion)
    expect(Object.values(again.changes).flat()).toEqual([])
    expect(again.currentVersion).toBe(pushed.currentVersion)
  })

  test('repeating the same push creates no duplicates', async () => {
    const { admin, token } = await start()
    const cat = await categoryId(token)
    const record = txn({ categoryId: cat, paidBy: admin.id })
    await sync(token, 0, { transactions: [record] })
    const second = await sync(token, 0, { transactions: [record] })
    expect(second.rejected).toEqual([])
    const rows = await t.db.select().from(transactions)
    expect(rows).toHaveLength(1)
    expect(second.changes.transactions).toHaveLength(1)
  })

  test('last write wins and both devices converge', async () => {
    const { admin, token } = await start()
    const b = await addMember(token)
    const cat = await categoryId(token)
    const record = txn({ categoryId: cat, paidBy: admin.id, note: 'original' })
    const base = await sync(token, 0, { transactions: [record] })
    const baseB = await sync(b.token, 0)
    // Both devices edit offline; A arrives first, then B.
    const fromA = await sync(token, base.currentVersion, { transactions: [{ ...record, note: 'von A' }] })
    const fromB = await sync(b.token, baseB.currentVersion, { transactions: [{ ...record, note: 'von B' }] })
    expect(fromB.changes.transactions).toEqual([expect.objectContaining({ id: record.id, note: 'von B' })])

    const pullA = await sync(token, fromA.currentVersion)
    expect(pullA.changes.transactions).toEqual([expect.objectContaining({ id: record.id, note: 'von B' })])
    expect(pullA.currentVersion).toBe(fromB.currentVersion)
    const [row] = await t.db.select().from(transactions).where(eq(transactions.id, record.id))
    expect(row!.note).toBe('von B')
  })

  test('soft delete is propagated', async () => {
    const { admin, token } = await start()
    const b = await addMember(token)
    const cat = await categoryId(token)
    const record = txn({ categoryId: cat, paidBy: admin.id })
    await sync(token, 0, { transactions: [record] })
    const baseB = await sync(b.token, 0)
    await sync(token, 0, { transactions: [{ ...record, deleted: true }] })
    const r = await sync(b.token, baseB.currentVersion)
    expect(r.changes.transactions).toEqual([expect.objectContaining({ id: record.id, deleted: true })])
  })

  test('invalid record is rejected alone', async () => {
    const { admin, token } = await start()
    const cat = await categoryId(token)
    const bad = txn({ categoryId: cat, paidBy: admin.id, amountCents: 0 })
    const good = txn({ categoryId: cat, paidBy: admin.id })
    const r = await sync(token, 0, { transactions: [bad, good] })
    expect(r.rejected).toHaveLength(1)
    expect(r.rejected[0]).toMatchObject({ table: 'transactions', id: bad.id })
    expect(r.rejected[0]!.reason).toContain('amountCents')
    const rows = await t.db.select().from(transactions)
    expect(rows.map((x) => x.id)).toEqual([good.id])
  })

  test('missing nullable keys (note, recurringRuleId, endDate) are accepted as null', async () => {
    // swift-openapi-generator encodes nil optionals by omitting the key instead of sending null.
    const { admin, token } = await start()
    const cat = await categoryId(token)
    const { note: _n, recurringRuleId: _r, ...record } = txn({ categoryId: cat, paidBy: admin.id })
    const { note: _rn, endDate: _e, ...ruleRecord } = rule({ categoryId: cat, paidBy: admin.id })
    const r = await sync(token, 0, { transactions: [record], recurringRules: [ruleRecord] })
    expect(r.rejected).toEqual([])
    expect(r.changes.transactions[0]).toMatchObject({ id: record.id, note: null, recurringRuleId: null })
    expect(r.changes.recurringRules[0]).toMatchObject({ id: ruleRecord.id, note: null, endDate: null })
    const [row] = await t.db.select().from(transactions).where(eq(transactions.id, record.id))
    expect(row).toMatchObject({ note: null, recurringRuleId: null })
    const [ruleRow] = await t.db.select().from(recurringRules).where(eq(recurringRules.id, ruleRecord.id))
    expect(ruleRow).toMatchObject({ note: null, endDate: null })
  })

  test('other missing required keys still reject the record', async () => {
    const { admin, token } = await start()
    const cat = await categoryId(token)
    const { date: _d, ...noDate } = txn({ categoryId: cat, paidBy: admin.id })
    const { startDate: _s, ...noStart } = rule({ categoryId: cat, paidBy: admin.id })
    const r = await sync(token, 0, { transactions: [noDate], recurringRules: [noStart] })
    expect(r.rejected.map((x) => x.id).sort()).toEqual([noDate.id, noStart.id].sort())
    expect(r.rejected.find((x) => x.id === noDate.id)!.reason).toContain('date')
    expect(r.rejected.find((x) => x.id === noStart.id)!.reason).toContain('startDate')
  })

  test('records that are not objects are rejected with id null', async () => {
    const { token } = await start()
    const r = await sync(token, 0, { transactions: [42, null], categories: ['x'] })
    expect(r.rejected).toHaveLength(3)
    expect(r.rejected.every((x) => x.id === null)).toBe(true)
    expect(r.rejected.map((x) => x.table).sort()).toEqual(['categories', 'transactions', 'transactions'])
  })

  test('invalid envelope → 400', async () => {
    const { token } = await start()
    for (const payload of [{ lastVersion: -1, changes: {} }, { lastVersion: 0 }, { lastVersion: 0, changes: { transactions: 'x' } }]) {
      const res = await t.app.inject({ method: 'POST', url: '/sync', headers: auth(token), payload })
      expect(res.statusCode).toBe(400)
      expect(res.json().error.code).toBe('validation_failed')
    }
  })

  test('unknown categoryId → rejected foreign_key_violation', async () => {
    const { admin, token } = await start()
    const record = txn({ categoryId: randomUUID(), paidBy: admin.id })
    const r = await sync(token, 0, { transactions: [record] })
    expect(r.rejected).toEqual([{ table: 'transactions', id: record.id, reason: 'foreign_key_violation' }])
    expect(await t.db.select().from(transactions)).toHaveLength(0)
  })

  test('paidBy of a deleted user → rejected unknown_user', async () => {
    const { admin, token } = await start()
    const b = await addMember(token)
    await t.db.update(users).set({ deleted: true }).where(eq(users.id, b.user.id))
    const cat = await categoryId(token)
    const record = txn({ categoryId: cat, paidBy: b.user.id })
    const r = await sync(token, 0, { transactions: [record], recurringRules: [rule({ categoryId: cat, paidBy: b.user.id })] })
    expect(r.rejected.map((x) => [x.table, x.reason]).sort()).toEqual([
      ['recurringRules', 'unknown_user'],
      ['transactions', 'unknown_user'],
    ])
    // Deleting a historical record that references the deleted user is still allowed.
    await t.db.insert(transactions).values({ ...txn({ categoryId: cat, paidBy: b.user.id }), id: record.id })
    const del = await sync(token, 0, { transactions: [{ ...record, deleted: true }] })
    expect(del.rejected).toEqual([])
    void admin
  })

  test('deleting a category in use → rejected category_in_use', async () => {
    const { admin, token } = await start()
    const first = await sync(token, 0)
    const cat = leafCategories(first.changes.categories)[0]!
    await sync(token, 0, { transactions: [txn({ categoryId: cat.id, paidBy: admin.id })] })
    const { version: _v, ...catRecord } = cat
    const r = await sync(token, 0, { categories: [{ ...catRecord, deleted: true }] })
    expect(r.rejected).toEqual([{ table: 'categories', id: cat.id, reason: 'category_in_use' }])
    const [row] = await t.db.select().from(categories).where(eq(categories.id, cat.id))
    expect(row!.deleted).toBe(false)

    // A category referenced only by an active rule is in use as well.
    const cat2 = leafCategories(first.changes.categories)[1]!
    await sync(token, 0, { recurringRules: [rule({ categoryId: cat2.id, paidBy: admin.id })] })
    const { version: _v2, ...cat2Record } = cat2
    const r2 = await sync(token, 0, { categories: [{ ...cat2Record, deleted: true }] })
    expect(r2.rejected).toEqual([{ table: 'categories', id: cat2.id, reason: 'category_in_use' }])
  })

  test('deleting a category together with its last transaction in one push succeeds', async () => {
    const { admin, token } = await start()
    const first = await sync(token, 0)
    const { version: _v, ...cat } = leafCategories(first.changes.categories)[0]!
    const record = txn({ categoryId: cat.id, paidBy: admin.id })
    await sync(token, 0, { transactions: [record] })
    const r = await sync(token, 0, {
      categories: [{ ...cat, deleted: true }],
      transactions: [{ ...record, deleted: true }],
    })
    expect(r.rejected).toEqual([])
    const [row] = await t.db.select().from(categories).where(eq(categories.id, cat.id))
    expect(row!.deleted).toBe(true)
  })

  test('deleting a category soft-deletes its active budgets', async () => {
    const { token } = await start()
    const first = await sync(token, 0)
    const { version: _v, ...cat } = leafCategories(first.changes.categories)[0]!
    const budget = { id: randomUUID(), deleted: false, categoryId: cat.id, monthlyLimitCents: 30000 }
    const withBudget = await sync(token, first.currentVersion, { budgets: [budget] })
    expect(withBudget.rejected).toEqual([])

    const r = await sync(token, withBudget.currentVersion, { categories: [{ ...cat, deleted: true }] })
    expect(r.rejected).toEqual([])
    expect(r.changes.categories).toEqual([expect.objectContaining({ id: cat.id, deleted: true })])
    expect(r.changes.budgets).toEqual([{ ...budget, deleted: true, version: expect.any(Number) }])
    const [row] = await t.db.select().from(budgets).where(eq(budgets.id, budget.id))
    expect(row!.deleted).toBe(true)
  })

  test('booking on a deleted category restores it as archived', async () => {
    const { admin, token } = await start()
    const first = await sync(token, 0)
    const { version: _v, ...cat } = leafCategories(first.changes.categories)[0]!
    const del = await sync(token, first.currentVersion, { categories: [{ ...cat, deleted: true }] })
    expect(del.rejected).toEqual([])
    expect(del.changes.categories).toEqual([expect.objectContaining({ id: cat.id, deleted: true })])

    const record = txn({ categoryId: cat.id, paidBy: admin.id })
    const r = await sync(token, del.currentVersion, { transactions: [record] })
    expect(r.rejected).toEqual([])
    expect(r.changes.transactions.map((x) => x.id)).toEqual([record.id])
    expect(r.changes.categories).toEqual([expect.objectContaining({ id: cat.id, deleted: false, archived: true })])
  })

  test('a rejected record leaves no partial state (category restore is rolled back)', async () => {
    const { token } = await start()
    const first = await sync(token, 0)
    const { version: _v, ...cat } = leafCategories(first.changes.categories)[0]!
    const del = await sync(token, 0, { categories: [{ ...cat, deleted: true }] })
    const record = txn({ categoryId: cat.id, paidBy: randomUUID() })
    const r = await sync(token, del.currentVersion, { transactions: [record] })
    expect(r.rejected).toEqual([{ table: 'transactions', id: record.id, reason: 'foreign_key_violation' }])
    expect(r.changes.categories).toEqual([])
    const [row] = await t.db.select().from(categories).where(eq(categories.id, cat.id))
    expect(row).toMatchObject({ deleted: true, archived: false })
  })

  test('lastVersion ahead of server → fullResync with all data', async () => {
    const { admin, token } = await start()
    const first = await sync(token, 0)
    const cat = leafCategories(first.changes.categories)[0]!.id
    const record = txn({ categoryId: cat, paidBy: admin.id })
    const r = await sync(token, first.currentVersion + 1000, { transactions: [record] })
    expect(r.fullResync).toBe(true)
    expect(r.rejected).toEqual([])
    expect(r.changes.categories).toHaveLength(48)
    expect(r.changes.users).toHaveLength(1)
    expect(r.changes.transactions.map((x) => x.id)).toEqual([record.id])
    expect(r.currentVersion).toBeGreaterThan(first.currentVersion)

    const normal = await sync(token, r.currentVersion)
    expect(normal.fullResync).toBe(false)
  })

  /** The SQL step of the restore procedure in docs/betrieb.md (keep both in sync). */
  const RESTORE_SQL = sql`
    UPDATE sync_meta SET resync_floor = setval('sync_version_seq', COALESCE(GREATEST(
      (SELECT max(version) FROM users),
      (SELECT max(version) FROM categories),
      (SELECT max(version) FROM transactions),
      (SELECT max(version) FROM budgets),
      (SELECT max(version) FROM recurring_rules),
      (SELECT last_value FROM sync_version_seq)
    ), 0) + 1000000)`

  test('after a backup restore, a client below the resync floor gets fullResync once; others do not', async () => {
    const { admin, token } = await start()
    const before = await sync(token, 0)
    const cat = leafCategories(before.changes.categories)[0]!.id
    // Device B synced before the backup was taken.
    const oldVersion = before.currentVersion
    // Simulate the restore step of docs/betrieb.md (as if a backup taken right now was restored).
    await t.db.execute(RESTORE_SQL)
    const [meta] = await t.db.execute<{ resync_floor: string }>(sql`SELECT resync_floor::text FROM sync_meta`)
    const floor = Number(meta!.resync_floor)
    expect(floor).toBe(oldVersion + 1000000)

    const resynced = await sync(token, oldVersion)
    expect(resynced.fullResync).toBe(true)
    expect(resynced.changes.categories).toHaveLength(48)
    expect(resynced.changes.users).toHaveLength(1)
    // No write since the restore: the floor is the current version, so the next sync is a normal one.
    expect(resynced.currentVersion).toBe(floor)

    const normal = await sync(token, resynced.currentVersion)
    expect(normal.fullResync).toBe(false)
    expect(normal.changes.categories).toEqual([])

    // New writes get versions above the floor; a client at the floor receives them incrementally.
    const record = txn({ categoryId: cat, paidBy: admin.id })
    const pushed = await sync(token, floor, { transactions: [record] })
    expect(pushed.fullResync).toBe(false)
    expect(pushed.changes.transactions.map((x) => x.version)[0]).toBeGreaterThan(floor)
    const later = await sync(token, pushed.currentVersion)
    expect(later.fullResync).toBe(false)
  })

  test('response serialization does not re-apply input refinements to stored rows', async () => {
    const { admin, token } = await start()
    const [cat] = await t.db
      .insert(categories)
      .values({ name: 'x'.repeat(60), icon: 'i'.repeat(150), color: '#123456', kind: 'expense' })
      .returning()
    await t.db.insert(recurringRules).values({
      amountCents: 100,
      kind: 'expense',
      categoryId: cat!.id,
      note: 'n'.repeat(300),
      paidBy: admin.id,
      frequency: 'monthly',
      startDate: '1999-01-01',
      endDate: '1998-01-01',
      nextDueDate: '1999-01-01',
    })
    const r = await sync(token, 0)
    expect(r.changes.categories.find((c) => c.id === cat!.id)).toMatchObject({ name: 'x'.repeat(60) })
    expect(r.changes.recurringRules).toHaveLength(1)
    expect(r.changes.recurringRules[0]).toMatchObject({ startDate: '1999-01-01', endDate: '1998-01-01' })
  })

  test('push bodies above 1 MiB are accepted; above 10 MiB → 413 payload_too_large', async () => {
    const { token } = await start()
    const big = await t.app.inject({
      method: 'POST',
      url: '/sync',
      headers: auth(token),
      payload: { lastVersion: 0, changes: {}, pad: 'x'.repeat(2 * 1024 * 1024) },
    })
    expect(big.statusCode, big.body).toBe(200)
    const tooBig = await t.app.inject({
      method: 'POST',
      url: '/sync',
      headers: auth(token),
      payload: { lastVersion: 0, changes: {}, pad: 'x'.repeat(11 * 1024 * 1024) },
    })
    expect(tooBig.statusCode).toBe(413)
    expect(tooBig.json()).toEqual({ error: { code: 'payload_too_large', message: expect.any(String) } })
  })

  test('ids of records rejected at parse time are lowercased', async () => {
    const { token } = await start()
    const upper = randomUUID().toUpperCase()
    const r = await sync(token, 0, { transactions: [{ id: upper, deleted: false }] })
    expect(r.rejected).toHaveLength(1)
    expect(r.rejected[0]!.id).toBe(upper.toLowerCase())
  })

  test('second budget for same category → rejected unique_violation', async () => {
    const { token } = await start()
    const cat = await categoryId(token)
    const b1 = { id: randomUUID(), deleted: false, categoryId: cat, monthlyLimitCents: 30000 }
    const b2 = { id: randomUUID(), deleted: false, categoryId: cat, monthlyLimitCents: 40000 }
    const r = await sync(token, 0, { budgets: [b1, b2] })
    expect(r.rejected).toEqual([{ table: 'budgets', id: b2.id, reason: 'unique_violation' }])
    expect(r.changes.budgets).toEqual([{ ...b1, version: expect.any(Number) }])
  })

  function category(over: { parentId?: string | null } & Record<string, unknown> = {}) {
    return {
      id: randomUUID(),
      deleted: false,
      name: 'Obst',
      icon: 'cart',
      color: '#00AA00',
      kind: 'expense' as const,
      sortOrder: 0,
      archived: false,
      ...over,
    }
  }

  test('category parentId round-trips and defaults to null', async () => {
    const { token } = await start()
    const parent = category({ name: 'Lebensmittel' })
    const r1 = await sync(token, 0, { categories: [parent] })
    expect(r1.rejected).toEqual([])
    expect(r1.changes.categories.find((c) => c.id === parent.id)).toMatchObject({ parentId: null })

    const child = category({ parentId: parent.id })
    const r2 = await sync(token, 0, { categories: [child] })
    expect(r2.rejected).toEqual([])
    expect(r2.changes.categories.find((c) => c.id === child.id)).toMatchObject({ parentId: parent.id })
  })

  test('push without parentId keeps the stored parent', async () => {
    const { token } = await start()
    const parent = category({ name: 'Lebensmittel' })
    const child = category({ parentId: parent.id })
    await sync(token, 0, { categories: [parent, child] })
    const { parentId: _p, ...oldApp } = child
    const r = await sync(token, 0, { categories: [{ ...oldApp, name: 'Gemüse' }] })
    expect(r.rejected).toEqual([])
    expect(r.changes.categories.find((c) => c.id === child.id)).toMatchObject({ name: 'Gemüse', parentId: parent.id })
  })

  test('push with explicit parentId null clears the parent', async () => {
    const { token } = await start()
    const parent = category({ name: 'Lebensmittel' })
    const child = category({ parentId: parent.id })
    await sync(token, 0, { categories: [parent, child] })
    const r = await sync(token, 0, { categories: [{ ...child, parentId: null }] })
    expect(r.rejected).toEqual([])
    expect(r.changes.categories.find((c) => c.id === child.id)).toMatchObject({ parentId: null })
  })

  describe('subcategories', () => {
    const rejectedAs = (r: SyncResult, id: string, reason: string) =>
      expect(r.rejected).toEqual([{ table: 'categories', id, reason }])

    async function storedCategory(id: string) {
      const [row] = await t.db.select().from(categories).where(eq(categories.id, id))
      return row!
    }

    async function withParentAndChild(token: string) {
      const parent = category({ name: 'Wohnen' })
      const child = category({ name: 'Strom', parentId: parent.id })
      const r = await sync(token, 0, { categories: [parent, child] })
      expect(r.rejected).toEqual([])
      return { parent, child }
    }

    const budget = (categoryId: string, monthlyLimitCents = 30000) => ({
      id: randomUUID(),
      deleted: false,
      categoryId,
      monthlyLimitCents,
    })

    test('rejects parent that does not exist or is deleted', async () => {
      const { token } = await start()
      const missing = category({ parentId: randomUUID() })
      rejectedAs(await sync(token, 0, { categories: [missing] }), missing.id, 'invalid_parent')

      const parent = category({ name: 'Alt' })
      await sync(token, 0, { categories: [parent] })
      await sync(token, 0, { categories: [{ ...parent, deleted: true }] })
      const child = category({ parentId: parent.id })
      rejectedAs(await sync(token, 0, { categories: [child] }), child.id, 'invalid_parent')
    })

    test('rejects parent that itself has a parent', async () => {
      const { token } = await start()
      const { child } = await withParentAndChild(token)
      const grandchild = category({ parentId: child.id })
      rejectedAs(await sync(token, 0, { categories: [grandchild] }), grandchild.id, 'invalid_parent')
    })

    test('rejects parent of the other kind', async () => {
      const { token } = await start()
      const parent = category({ name: 'Gehalt', kind: 'income' })
      await sync(token, 0, { categories: [parent] })
      const child = category({ parentId: parent.id })
      rejectedAs(await sync(token, 0, { categories: [child] }), child.id, 'invalid_parent')
    })

    test('rejects giving a parent to a category that has children', async () => {
      const { token } = await start()
      const { parent } = await withParentAndChild(token)
      const other = category({ name: 'Haushalt' })
      await sync(token, 0, { categories: [other] })
      rejectedAs(await sync(token, 0, { categories: [{ ...parent, parentId: other.id }] }), parent.id, 'invalid_parent')
      expect((await storedCategory(parent.id)).parentId).toBeNull()
    })

    test('rejects changing kind of a category with children', async () => {
      const { token } = await start()
      const { parent } = await withParentAndChild(token)
      rejectedAs(await sync(token, 0, { categories: [{ ...parent, kind: 'income' }] }), parent.id, 'invalid_parent')
      expect((await storedCategory(parent.id)).kind).toBe('expense')
    })

    test('rejects self as parent', async () => {
      const { token } = await start()
      const cat = category()
      await sync(token, 0, { categories: [cat] })
      rejectedAs(await sync(token, 0, { categories: [{ ...cat, parentId: cat.id }] }), cat.id, 'invalid_parent')
    })

    test('rejects deleting a category with active children', async () => {
      const { token } = await start()
      const { parent, child } = await withParentAndChild(token)
      rejectedAs(
        await sync(token, 0, { categories: [{ ...parent, deleted: true }] }),
        parent.id,
        'category_has_children',
      )
      expect((await storedCategory(parent.id)).deleted).toBe(false)

      expect((await sync(token, 0, { categories: [{ ...child, deleted: true }] })).rejected).toEqual([])
      expect((await sync(token, 0, { categories: [{ ...parent, deleted: true }] })).rejected).toEqual([])
      expect((await storedCategory(parent.id)).deleted).toBe(true)
    })

    test('accepts parent and child in one push in any order', async () => {
      const { token } = await start()
      const parent = category({ name: 'Wohnen' })
      const child = category({ name: 'Strom', parentId: parent.id })
      const r = await sync(token, 0, { categories: [child, parent] })
      expect(r.rejected).toEqual([])
      expect((await storedCategory(child.id)).parentId).toBe(parent.id)
    })

    test('deletes child and parent in one push in any order', async () => {
      const { token } = await start()
      const { parent, child } = await withParentAndChild(token)
      const r = await sync(token, 0, {
        categories: [
          { ...parent, deleted: true },
          { ...child, deleted: true },
        ],
      })
      expect(r.rejected).toEqual([])
      expect((await storedCategory(parent.id)).deleted).toBe(true)
      expect((await storedCategory(child.id)).deleted).toBe(true)
    })

    test('rejects budget on a subcategory', async () => {
      const { token } = await start()
      const { child } = await withParentAndChild(token)
      const b = budget(child.id)
      const r = await sync(token, 0, { budgets: [b] })
      expect(r.rejected).toEqual([{ table: 'budgets', id: b.id, reason: 'budget_on_subcategory' }])
      expect(await t.db.select().from(budgets)).toEqual([])
    })

    test('moving a budgeted category under a parent without budget moves the budget', async () => {
      const { token } = await start()
      const parent = category({ name: 'Wohnen' })
      const cat = category({ name: 'Strom' })
      const b = budget(cat.id)
      const before = await sync(token, 0, { categories: [parent, cat], budgets: [b] })
      expect(before.rejected).toEqual([])

      const r = await sync(token, before.currentVersion, { categories: [{ ...cat, parentId: parent.id }] })
      expect(r.rejected).toEqual([])
      expect(r.changes.budgets).toEqual([{ ...b, categoryId: parent.id, version: expect.any(Number) }])
      expect(r.changes.budgets[0]!.version).toBeGreaterThan(before.currentVersion)
    })

    test('moving a budgeted category under a parent with budget deletes its budget', async () => {
      const { token } = await start()
      const parent = category({ name: 'Wohnen' })
      const cat = category({ name: 'Strom' })
      const parentBudget = budget(parent.id, 100000)
      const catBudget = budget(cat.id)
      const before = await sync(token, 0, { categories: [parent, cat], budgets: [parentBudget, catBudget] })
      expect(before.rejected).toEqual([])

      const r = await sync(token, before.currentVersion, { categories: [{ ...cat, parentId: parent.id }] })
      expect(r.rejected).toEqual([])
      expect(r.changes.budgets).toEqual([{ ...catBudget, deleted: true, version: expect.any(Number) }])
      const active = await t.db.select().from(budgets).where(eq(budgets.deleted, false))
      expect(active.map((x) => x.id)).toEqual([parentBudget.id])
    })

    test('transaction on a deleted subcategory revives it and its deleted parent', async () => {
      const { admin, token } = await start()
      const { parent, child } = await withParentAndChild(token)
      const del = await sync(token, 0, {
        categories: [
          { ...child, deleted: true },
          { ...parent, deleted: true },
        ],
      })
      expect(del.rejected).toEqual([])

      const r = await sync(token, del.currentVersion, { transactions: [txn({ categoryId: child.id, paidBy: admin.id })] })
      expect(r.rejected).toEqual([])
      expect(r.changes.categories.map((c) => c.id).sort()).toEqual([parent.id, child.id].sort())
      for (const c of r.changes.categories) expect(c).toMatchObject({ deleted: false, archived: true })
    })

    test.each([
      ['moved under another category', (parent: ReturnType<typeof category>, other: ReturnType<typeof category>) => ({ ...parent, parentId: other.id })],
      ['changed kind', (parent: ReturnType<typeof category>) => ({ ...parent, kind: 'income' as const })],
    ])('reviving a subcategory whose parent was %s brings it back as top-level', async (_label, changeParent) => {
      const { admin, token } = await start()
      const { parent, child } = await withParentAndChild(token)
      const other = category({ name: 'Haushalt' })
      const setup = await sync(token, 0, { categories: [other, { ...child, deleted: true }] })
      expect(setup.rejected).toEqual([])
      const changed = await sync(token, 0, { categories: [changeParent(parent, other)] })
      expect(changed.rejected).toEqual([])

      const r = await sync(token, changed.currentVersion, {
        transactions: [txn({ categoryId: child.id, paidBy: admin.id })],
      })
      expect(r.rejected).toEqual([])
      expect(r.changes.categories).toEqual([
        expect.objectContaining({ id: child.id, deleted: false, archived: true, parentId: null }),
      ])
    })
  })

  test('new recurring rule gets nextDueDate = startDate', async () => {
    const onRulesChanged = async () => {}
    const { admin, token } = await start({ onRulesChanged })
    const cat = await categoryId(token)
    const record = rule({ categoryId: cat, paidBy: admin.id, startDate: '2026-02-01' })
    const r = await sync(token, 0, { recurringRules: [{ ...record, nextDueDate: '2030-01-01' }] })
    expect(r.rejected).toEqual([])
    expect(r.changes.recurringRules).toEqual([{ ...record, interval: 1, nextDueDate: '2026-02-01', version: expect.any(Number) }])
  })

  test('interval is stored and returned; changing it recomputes nextDueDate', async () => {
    // No generator here: it would book the due occurrence and move nextDueDate on, hiding the recompute.
    const { admin, token } = await start({ onRulesChanged: async () => {} })
    const cat = await categoryId(token)
    const record = rule({ categoryId: cat, paidBy: admin.id, startDate: '2025-11-15', interval: 3 })
    const created = await sync(token, 0, { recurringRules: [record] })
    expect(created.rejected).toEqual([])
    expect(created.changes.recurringRules[0]).toMatchObject({ interval: 3 })

    await t.db.update(recurringRules).set({ nextDueDate: '2026-02-15' }).where(eq(recurringRules.id, record.id))
    // Today is 2026-01-15. Every 2 months from 2025-11-15: 2025-11-15, 2026-01-15, … → first >= today is 2026-01-15.
    const every2 = await sync(token, 0, { recurringRules: [{ ...record, interval: 2 }] })
    expect(every2.changes.recurringRules[0]).toMatchObject({ interval: 2, nextDueDate: '2026-01-15' })
    // Every 4 months from 2025-11-15: 2025-11-15, 2026-03-15, … → 2026-03-15.
    const every4 = await sync(token, 0, { recurringRules: [{ ...record, interval: 4 }] })
    expect(every4.changes.recurringRules[0]).toMatchObject({ interval: 4, nextDueDate: '2026-03-15' })
  })

  test('a push without interval keeps the stored interval (older apps), new rules default to 1', async () => {
    const { admin, token } = await start()
    const cat = await categoryId(token)
    const withoutInterval = rule({ categoryId: cat, paidBy: admin.id })
    const quarterly = { ...withoutInterval, interval: 3 }
    await sync(token, 0, { recurringRules: [quarterly] })
    const r = await sync(token, 0, { recurringRules: [{ ...withoutInterval, note: 'Grundsteuer' }] })
    expect(r.changes.recurringRules.find((x) => x.id === quarterly.id)).toMatchObject({ interval: 3, note: 'Grundsteuer' })

    const fresh = rule({ categoryId: cat, paidBy: admin.id })
    const r2 = await sync(token, 0, { recurringRules: [fresh] })
    expect(r2.changes.recurringRules.find((x) => x.id === fresh.id)).toMatchObject({ interval: 1 })
  })

  test.each([0, 25, 1.5, '3'])('interval %j is rejected', async (interval) => {
    const { admin, token } = await start()
    const cat = await categoryId(token)
    const r = await sync(token, 0, { recurringRules: [rule({ categoryId: cat, paidBy: admin.id, interval })] })
    expect(r.rejected).toHaveLength(1)
    expect(r.rejected[0]).toMatchObject({ table: 'recurringRules' })
  })

  test('changing startDate/frequency recomputes nextDueDate as first occurrence >= today; other edits keep it', async () => {
    const { admin, token } = await start()
    const cat = await categoryId(token)
    const record = rule({ categoryId: cat, paidBy: admin.id, startDate: '2026-03-10' })
    await sync(token, 0, { recurringRules: [record] })

    // Edit only the note: nextDueDate stays as stored on the server.
    await t.db.update(recurringRules).set({ nextDueDate: '2026-04-10' }).where(eq(recurringRules.id, record.id))
    const noteOnly = await sync(token, 0, { recurringRules: [{ ...record, note: 'Miete neu' }] })
    expect(noteOnly.changes.recurringRules[0]).toMatchObject({ note: 'Miete neu', nextDueDate: '2026-04-10' })

    // startDate in the past: first occurrence >= 2026-01-15 anchored at 2025-11-05 is 2026-02-05.
    const moved = await sync(token, 0, { recurringRules: [{ ...record, startDate: '2025-11-05' }] })
    expect(moved.changes.recurringRules[0]).toMatchObject({ startDate: '2025-11-05', nextDueDate: '2026-02-05' })

    // frequency change: weekly from 2025-11-05 (Wed) → first >= 2026-01-15 is 2026-01-21.
    const weekly = await sync(token, 0, { recurringRules: [{ ...record, startDate: '2025-11-05', frequency: 'weekly' }] })
    expect(weekly.changes.recurringRules[0]).toMatchObject({ frequency: 'weekly', nextDueDate: '2026-01-21' })
  })

  test('onRulesChanged runs after a sync that changed rules and its writes are in the response', async () => {
    let calls = 0
    let catForHook = ''
    let paidBy = ''
    const generatedId = randomUUID()
    const onRulesChanged = async () => {
      calls++
      await t.db.insert(transactions).values(txn({ id: generatedId, categoryId: catForHook, paidBy }))
    }
    const { admin, token } = await start({ onRulesChanged })
    paidBy = admin.id
    catForHook = await categoryId(token)

    const none = await sync(token, 0, { transactions: [txn({ categoryId: catForHook, paidBy })] })
    expect(calls).toBe(0)
    expect(none.changes.transactions).toHaveLength(1)

    const r = await sync(token, none.currentVersion, { recurringRules: [rule({ categoryId: catForHook, paidBy })] })
    expect(calls).toBe(1)
    expect(r.changes.recurringRules).toHaveLength(1)
    expect(r.changes.transactions.map((x) => x.id)).toEqual([generatedId])
    const max = await t.db.execute<{ v: string }>(sql`SELECT max(version)::text AS v FROM transactions`)
    expect(r.currentVersion).toBe(Number(max[0]!.v))
  })

  test('NUL character in a text field rejects only that record', async () => {
    const { admin, token } = await start()
    const cat = await categoryId(token)
    const bad = txn({ categoryId: cat, paidBy: admin.id, note: 'a\u0000b' })
    const good = txn({ categoryId: cat, paidBy: admin.id })
    const r = await sync(token, 0, { transactions: [bad, good] })
    expect(r.rejected).toHaveLength(1)
    expect(r.rejected[0]).toMatchObject({ table: 'transactions', id: bad.id })
    expect(r.rejected[0]!.reason).toContain('note')
    expect((await t.db.select().from(transactions)).map((x) => x.id)).toEqual([good.id])
  })

  test('uppercase uuids are normalised: edit keeps unchanged paidBy of a removed member, no duplicate', async () => {
    const { token } = await start()
    const b = await addMember(token)
    const cat = await categoryId(token)
    const record = txn({ categoryId: cat, paidBy: b.user.id, note: 'alt' })
    await sync(token, 0, { transactions: [record] })
    await t.db.update(users).set({ deleted: true }).where(eq(users.id, b.user.id))

    const upper = {
      ...record,
      id: record.id.toUpperCase(),
      categoryId: cat.toUpperCase(),
      paidBy: b.user.id.toUpperCase(),
      note: 'neu',
    }
    const r = await sync(token, 0, { transactions: [upper] })
    expect(r.rejected).toEqual([])
    expect(r.changes.transactions).toEqual([
      expect.objectContaining({ id: record.id, categoryId: cat, paidBy: b.user.id, note: 'neu' }),
    ])
    const rows = await t.db.select().from(transactions)
    expect(rows).toHaveLength(1)
    expect(rows[0]).toMatchObject({ id: record.id, note: 'neu' })
  })

  test('recurring rule date rules: startDate >= 2000-01-01, endDate >= startDate', async () => {
    const { admin, token } = await start()
    const cat = await categoryId(token)
    const early = rule({ categoryId: cat, paidBy: admin.id, startDate: '1999-12-31' })
    const backwards = rule({ categoryId: cat, paidBy: admin.id, startDate: '2026-02-01', endDate: '2026-01-31' })
    const sameDay = rule({ categoryId: cat, paidBy: admin.id, startDate: '2026-02-01', endDate: '2026-02-01' })
    const r = await sync(token, 0, { recurringRules: [early, backwards, sameDay] })
    expect(r.rejected.map((x) => x.id).sort()).toEqual([early.id, backwards.id].sort())
    expect(r.rejected.find((x) => x.id === early.id)!.reason).toContain('startDate')
    expect(r.rejected.find((x) => x.id === backwards.id)!.reason).toContain('endDate')
    expect(r.changes.recurringRules.map((x) => x.id)).toEqual([sameDay.id])
  })

  test('lastVersion above MAX_SAFE_INTEGER → 400', async () => {
    const { token } = await start()
    const res = await t.app.inject({
      method: 'POST',
      url: '/sync',
      headers: auth(token),
      payload: { lastVersion: Number.MAX_SAFE_INTEGER + 2, changes: {} },
    })
    expect(res.statusCode).toBe(400)
  })

  test('sync without token → 401', async () => {
    t = await createTestApp()
    const res = await t.app.inject({ method: 'POST', url: '/sync', payload: { lastVersion: 0, changes: {} } })
    expect(res.statusCode).toBe(401)
  })
})
