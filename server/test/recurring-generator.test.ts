import { randomUUID } from 'node:crypto'
import { and, eq } from 'drizzle-orm'
import { afterEach, describe, expect, test, vi } from 'vitest'
import { todayIn } from '../src/clock.js'
import { categories, recurringRules, refreshTokens, transactions } from '../src/db/schema.js'
import { generateDueTransactions } from '../src/recurring/generator.js'
import { startScheduler } from '../src/recurring/scheduler.js'
import { createTestApp, login, setupAdmin } from './helpers.js'

type TestApp = Awaited<ReturnType<typeof createTestApp>>

describe('generateDueTransactions', () => {
  let t: TestApp
  afterEach(async () => {
    await t?.close()
  })

  async function start(opts: Parameters<typeof createTestApp>[0] = {}) {
    t = await createTestApp(opts)
    const admin = await setupAdmin(t.app)
    const [cat] = await t.db.select().from(categories).where(eq(categories.kind, 'expense')).limit(1)
    return { adminId: admin.id, categoryId: cat!.id }
  }

  async function addRule(
    ctx: { adminId: string; categoryId: string },
    over: Partial<typeof recurringRules.$inferInsert> = {},
  ) {
    const startDate = over.startDate ?? '2026-01-01'
    const [row] = await t.db
      .insert(recurringRules)
      .values({
        amountCents: 80000,
        kind: 'expense',
        categoryId: ctx.categoryId,
        note: 'Miete',
        paidBy: ctx.adminId,
        frequency: 'monthly',
        startDate,
        nextDueDate: startDate,
        ...over,
      })
      .returning()
    return row!
  }

  const txnsOf = (ruleId: string) =>
    t.db.select().from(transactions).where(eq(transactions.recurringRuleId, ruleId)).orderBy(transactions.date)

  test('generates due transactions and advances nextDueDate', async () => {
    const ctx = await start()
    const rule = await addRule(ctx, { startDate: '2026-01-10' })
    const n = await generateDueTransactions(t.db, '2026-01-15')
    expect(n).toBe(1)
    const rows = await txnsOf(rule.id)
    expect(rows).toHaveLength(1)
    expect(rows[0]).toMatchObject({
      date: '2026-01-10',
      amountCents: 80000,
      kind: 'expense',
      categoryId: ctx.categoryId,
      note: 'Miete',
      paidBy: ctx.adminId,
      deleted: false,
    })
    const [after] = await t.db.select().from(recurringRules).where(eq(recurringRules.id, rule.id))
    expect(after!.nextDueDate).toBe('2026-02-10')
    expect(after!.version).toBeGreaterThan(rule.version)
  })

  test('running twice on the same day creates nothing new', async () => {
    const ctx = await start()
    const rule = await addRule(ctx, { startDate: '2026-01-10' })
    await generateDueTransactions(t.db, '2026-01-15')
    const [mid] = await t.db.select().from(recurringRules).where(eq(recurringRules.id, rule.id))
    expect(await generateDueTransactions(t.db, '2026-01-15')).toBe(0)
    expect(await txnsOf(rule.id)).toHaveLength(1)
    const [end] = await t.db.select().from(recurringRules).where(eq(recurringRules.id, rule.id))
    expect(end!.version).toBe(mid!.version)
  })

  test('catches up missed months after downtime', async () => {
    const ctx = await start()
    const rule = await addRule(ctx, { startDate: '2026-01-31' })
    expect(await generateDueTransactions(t.db, '2026-04-30')).toBe(4)
    expect((await txnsOf(rule.id)).map((r) => r.date)).toEqual(['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30'])
    const [after] = await t.db.select().from(recurringRules).where(eq(recurringRules.id, rule.id))
    expect(after!.nextDueDate).toBe('2026-05-31')
  })

  test('a deleted generated transaction is not recreated', async () => {
    const ctx = await start()
    const rule = await addRule(ctx, { startDate: '2026-01-10' })
    await generateDueTransactions(t.db, '2026-01-15')
    await t.db.update(transactions).set({ deleted: true }).where(eq(transactions.recurringRuleId, rule.id))
    // Even if nextDueDate were rewound, the unique index keeps the tombstone authoritative.
    await t.db.update(recurringRules).set({ nextDueDate: '2026-01-10' }).where(eq(recurringRules.id, rule.id))
    expect(await generateDueTransactions(t.db, '2026-01-15')).toBe(0)
    const rows = await txnsOf(rule.id)
    expect(rows).toHaveLength(1)
    expect(rows[0]!.deleted).toBe(true)
  })

  test('uses Berlin date shortly after midnight', async () => {
    const ctx = await start({ now: '2026-10-31T23:30:00Z' })
    const rule = await addRule(ctx, { startDate: '2026-11-01' })
    const today = todayIn(t.clock, 'Europe/Berlin')
    expect(today).toBe('2026-11-01')
    expect(await generateDueTransactions(t.db, today)).toBe(1)
    expect((await txnsOf(rule.id)).map((r) => r.date)).toEqual(['2026-11-01'])
  })

  test('deleted rule generates nothing', async () => {
    const ctx = await start()
    const rule = await addRule(ctx, { startDate: '2026-01-10', deleted: true })
    expect(await generateDueTransactions(t.db, '2026-03-01')).toBe(0)
    expect(await txnsOf(rule.id)).toHaveLength(0)
  })

  test('respects endDate', async () => {
    const ctx = await start()
    const rule = await addRule(ctx, { startDate: '2026-01-10', endDate: '2026-02-15' })
    expect(await generateDueTransactions(t.db, '2026-06-01')).toBe(2)
    expect(await txnsOf(rule.id)).toHaveLength(2)
  })

  test('sync creating a rule returns its generated transactions in the same response', async () => {
    t = await createTestApp({ now: '2026-01-15T12:00:00Z' })
    const admin = await setupAdmin(t.app)
    const { accessToken } = await login(t.app, 'admin', 'geheim123')
    const headers = { authorization: `Bearer ${accessToken}` }
    const first = await t.app.inject({ method: 'POST', url: '/sync', headers, payload: { lastVersion: 0, changes: {} } })
    const cat = first.json().changes.categories.find((c: { kind: string }) => c.kind === 'expense').id
    const ruleId = randomUUID()
    const res = await t.app.inject({
      method: 'POST',
      url: '/sync',
      headers,
      payload: {
        lastVersion: first.json().currentVersion,
        changes: {
          recurringRules: [
            {
              id: ruleId,
              deleted: false,
              amountCents: 80000,
              kind: 'expense',
              categoryId: cat,
              note: 'Miete',
              paidBy: admin.id,
              frequency: 'monthly',
              startDate: '2026-01-10',
              endDate: null,
            },
          ],
        },
      },
    })
    expect(res.statusCode, res.body).toBe(200)
    const body = res.json()
    expect(body.changes.transactions).toHaveLength(1)
    expect(body.changes.transactions[0]).toMatchObject({ recurringRuleId: ruleId, date: '2026-01-10' })
    expect(body.changes.recurringRules[0]).toMatchObject({ id: ruleId, nextDueDate: '2026-02-10' })
  })
})

describe('startScheduler', () => {
  let t: TestApp
  afterEach(async () => {
    await t?.close()
  })

  test('runs once immediately (generation + refresh-token pruning), uses clock/time zone, and stops; errors are logged', async () => {
    t = await createTestApp({ now: '2026-10-31T23:30:00Z' })
    const admin = await setupAdmin(t.app)
    const [cat] = await t.db.select().from(categories).limit(1)
    const [rule] = await t.db
      .insert(recurringRules)
      .values({
        amountCents: 500,
        kind: 'expense',
        categoryId: cat!.id,
        paidBy: admin.id,
        frequency: 'monthly',
        startDate: '2026-11-01',
        nextDueDate: '2026-11-01',
      })
      .returning()
    const now = t.clock.now().getTime()
    await t.db.insert(refreshTokens).values([
      { userId: admin.id, tokenHash: 'expired', expiresAt: new Date(now - 1000) },
      { userId: admin.id, tokenHash: 'valid', expiresAt: new Date(now + 60_000) },
    ])
    const handle = startScheduler(t.db, t.clock, 'Europe/Berlin')
    try {
      await vi.waitFor(async () => {
        const rows = await t.db
          .select()
          .from(transactions)
          .where(and(eq(transactions.recurringRuleId, rule!.id)))
        expect(rows).toHaveLength(1)
        const tokens = await t.db.select({ tokenHash: refreshTokens.tokenHash }).from(refreshTokens)
        expect(tokens).toEqual([{ tokenHash: 'valid' }])
      })
    } finally {
      handle.stop()
    }
    expect(() => handle.stop()).not.toThrow()

    const logged: unknown[] = []
    const broken = { ...t.db, transaction: () => Promise.reject(new Error('boom')) } as unknown as typeof t.db
    const h2 = startScheduler(broken, t.clock, 'Europe/Berlin', { error: (o) => logged.push(o) })
    try {
      // Both jobs fail on the broken db; one failure does not skip the other.
      await vi.waitFor(() => expect(logged).toHaveLength(2))
    } finally {
      h2.stop()
    }
  })
})
