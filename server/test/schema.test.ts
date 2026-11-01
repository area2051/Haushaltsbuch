import { eq } from 'drizzle-orm'
import { afterEach, expect, test } from 'vitest'
import { createTestApp } from './helpers.js'
import { budgets, categories, recurringRules, transactions, users } from '../src/db/schema.js'

let close: (() => Promise<void>) | undefined
afterEach(async () => {
  await close?.()
  close = undefined
})

async function seed() {
  const ctx = await createTestApp()
  close = ctx.close
  const { db } = ctx
  const [u] = await db
    .insert(users)
    .values({ username: 'a', displayName: 'A', passwordHash: 'x', isAdmin: true })
    .returning()
  const [c] = await db
    .insert(categories)
    .values({ name: 'X', icon: 'cart', color: '#000000', kind: 'expense', sortOrder: 0 })
    .returning()
  return { db, u: u!, c: c! }
}

test('versions come from one shared sequence', async () => {
  const { u, c } = await seed()
  expect(c.version).toBeGreaterThan(u.version)
  expect(typeof c.version).toBe('number')
})

test('rejects duplicate generated transaction for same rule and date', async () => {
  const { db, u, c } = await seed()
  const [r] = await db
    .insert(recurringRules)
    .values({
      amountCents: 100,
      kind: 'expense',
      categoryId: c.id,
      paidBy: u.id,
      frequency: 'monthly',
      startDate: '2026-01-01',
      nextDueDate: '2026-01-01',
    })
    .returning()
  const row = {
    amountCents: 100,
    kind: 'expense' as const,
    categoryId: c.id,
    date: '2026-01-01',
    paidBy: u.id,
    recurringRuleId: r!.id,
  }
  await db.insert(transactions).values(row)
  await expect(db.insert(transactions).values(row)).rejects.toThrow()
  // without a rule, duplicates are fine
  const plain = { ...row, recurringRuleId: null }
  await db.insert(transactions).values(plain)
  await db.insert(transactions).values(plain)
})

test('allows a new budget after the old one was soft-deleted', async () => {
  const { db, c } = await seed()
  const [b] = await db.insert(budgets).values({ categoryId: c.id, monthlyLimitCents: 1000 }).returning()
  await expect(db.insert(budgets).values({ categoryId: c.id, monthlyLimitCents: 2000 })).rejects.toThrow()
  await db.update(budgets).set({ deleted: true }).where(eq(budgets.id, b!.id))
  await db.insert(budgets).values({ categoryId: c.id, monthlyLimitCents: 2000 })
})

test('rejects amount_cents = 0', async () => {
  const { db, u, c } = await seed()
  await expect(
    db.insert(transactions).values({
      amountCents: 0,
      kind: 'expense',
      categoryId: c.id,
      date: '2026-01-01',
      paidBy: u.id,
    }),
  ).rejects.toThrow()
})
