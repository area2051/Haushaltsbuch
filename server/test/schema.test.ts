import { eq } from 'drizzle-orm'
import { afterEach, expect, test } from 'vitest'
import { createTestApp } from './helpers.js'
import { budgets, categories, recurringRules, transactions, users } from '../src/db/schema.js'

async function pgError(p: Promise<unknown>): Promise<{ code?: string; constraint_name?: string }> {
  try {
    await p
  } catch (e) {
    const err = e as { code?: string; constraint_name?: string; cause?: unknown }
    return err.code ? err : ((err.cause ?? {}) as { code?: string; constraint_name?: string })
  }
  throw new Error('expected insert to fail')
}

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
  const e1 = await pgError(db.insert(transactions).values(row))
  expect(e1.code).toBe('23505')
  expect(e1.constraint_name).toBe('transactions_rule_date_uq')
  // without a rule, duplicates are fine
  const plain = { ...row, recurringRuleId: null }
  await db.insert(transactions).values(plain)
  await db.insert(transactions).values(plain)
})

test('allows a new budget after the old one was soft-deleted', async () => {
  const { db, c } = await seed()
  const [b] = await db.insert(budgets).values({ categoryId: c.id, monthlyLimitCents: 1000 }).returning()
  const e2 = await pgError(db.insert(budgets).values({ categoryId: c.id, monthlyLimitCents: 2000 }))
  expect(e2.code).toBe('23505')
  expect(e2.constraint_name).toBe('budgets_category_active_uq')
  await db.update(budgets).set({ deleted: true }).where(eq(budgets.id, b!.id))
  await db.insert(budgets).values({ categoryId: c.id, monthlyLimitCents: 2000 })
})

test('rejects amount_cents = 0', async () => {
  const { db, u, c } = await seed()
  const e = await pgError(
    db.insert(transactions).values({
      amountCents: 0,
      kind: 'expense',
      categoryId: c.id,
      date: '2026-01-01',
      paidBy: u.id,
    }),
  )
  expect(e.code).toBe('23514')
  expect(e.constraint_name).toBe('transactions_amount_positive')
})

test('rejects recurring rule with amount_cents = 0', async () => {
  const { db, u, c } = await seed()
  const e = await pgError(
    db.insert(recurringRules).values({
      amountCents: 0,
      kind: 'expense',
      categoryId: c.id,
      paidBy: u.id,
      frequency: 'monthly',
      startDate: '2026-01-01',
      nextDueDate: '2026-01-01',
    }),
  )
  expect(e.code).toBe('23514')
  expect(e.constraint_name).toBe('recurring_rules_amount_positive')
})
