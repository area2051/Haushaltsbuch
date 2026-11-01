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
    expect(r.changes.categories).toHaveLength(10)
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
    const cat = first.changes.categories[0]!.id
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
    const cat = first.changes.categories[0]!
    await sync(token, 0, { transactions: [txn({ categoryId: cat.id, paidBy: admin.id })] })
    const { version: _v, ...catRecord } = cat
    const r = await sync(token, 0, { categories: [{ ...catRecord, deleted: true }] })
    expect(r.rejected).toEqual([{ table: 'categories', id: cat.id, reason: 'category_in_use' }])
    const [row] = await t.db.select().from(categories).where(eq(categories.id, cat.id))
    expect(row!.deleted).toBe(false)

    // A category referenced only by an active rule is in use as well.
    const cat2 = first.changes.categories[1]!
    await sync(token, 0, { recurringRules: [rule({ categoryId: cat2.id, paidBy: admin.id })] })
    const { version: _v2, ...cat2Record } = cat2
    const r2 = await sync(token, 0, { categories: [{ ...cat2Record, deleted: true }] })
    expect(r2.rejected).toEqual([{ table: 'categories', id: cat2.id, reason: 'category_in_use' }])
  })

  test('deleting a category together with its last transaction in one push succeeds', async () => {
    const { admin, token } = await start()
    const first = await sync(token, 0)
    const { version: _v, ...cat } = first.changes.categories[0]!
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
    const { version: _v, ...cat } = first.changes.categories[0]!
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
    const { version: _v, ...cat } = first.changes.categories[0]!
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
    const { version: _v, ...cat } = first.changes.categories[0]!
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
    const cat = first.changes.categories[0]!.id
    const record = txn({ categoryId: cat, paidBy: admin.id })
    const r = await sync(token, first.currentVersion + 1000, { transactions: [record] })
    expect(r.fullResync).toBe(true)
    expect(r.rejected).toEqual([])
    expect(r.changes.categories).toHaveLength(10)
    expect(r.changes.users).toHaveLength(1)
    expect(r.changes.transactions.map((x) => x.id)).toEqual([record.id])
    expect(r.currentVersion).toBeGreaterThan(first.currentVersion)

    const normal = await sync(token, r.currentVersion)
    expect(normal.fullResync).toBe(false)
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

  test('new recurring rule gets nextDueDate = startDate', async () => {
    const onRulesChanged = async () => {}
    const { admin, token } = await start({ onRulesChanged })
    const cat = await categoryId(token)
    const record = rule({ categoryId: cat, paidBy: admin.id, startDate: '2026-02-01' })
    const r = await sync(token, 0, { recurringRules: [{ ...record, nextDueDate: '2030-01-01' }] })
    expect(r.rejected).toEqual([])
    expect(r.changes.recurringRules).toEqual([{ ...record, nextDueDate: '2026-02-01', version: expect.any(Number) }])
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
