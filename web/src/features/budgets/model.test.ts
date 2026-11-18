import { expect, test } from 'vitest'
import { budget, cat, tx } from '../../test/fixtures'
import { budgetRecord, budgetRows, removedBudget } from './model'

const M = '2026-11'

test('one row per active expense category in sort order, with spending and budget', () => {
  const cats = [
    cat('b', 'expense', { sortOrder: 2 }),
    cat('a', 'expense', { sortOrder: 1 }),
    cat('pay', 'income'),
    cat('old', 'expense', { archived: true }),
  ]
  const b = budget('a', 1000)
  const rows = budgetRows(cats, [b], [tx(800, '2026-11-03', { categoryId: 'a' }), tx(300, '2026-11-03', { categoryId: 'b' }), tx(999, '2026-10-03', { categoryId: 'a' })], M)
  expect(rows.items.map((r) => [r.category.id, r.spentCents, r.budget?.id ?? null, r.progress?.level ?? null])).toEqual([
    ['a', 800, b.id, 'warning'],
    ['b', 300, null, null],
  ])
})

test('totals sum limits and the spending of budgeted categories only', () => {
  const cats = [cat('a'), cat('b'), cat('c')]
  const rows = budgetRows(cats, [budget('a', 1000), budget('b', 500)], [tx(200, '2026-11-01', { categoryId: 'a' }), tx(100, '2026-11-01', { categoryId: 'b' }), tx(5000, '2026-11-01', { categoryId: 'c' })], M)
  expect(rows.total).toEqual({ limitCents: 1500, spentCents: 300 })
})

test('setting a budget updates the existing record of the category', () => {
  const existing = budget('a', 1000)
  expect(budgetRecord(existing, 'a', 2500, 'new-id')).toEqual({ id: existing.id, categoryId: 'a', monthlyLimitCents: 2500, deleted: false })
  expect(budgetRecord(undefined, 'a', 2500, 'new-id')).toEqual({ id: 'new-id', categoryId: 'a', monthlyLimitCents: 2500, deleted: false })
})

test('removing a budget soft-deletes it', () => {
  const existing = budget('a', 1000)
  expect(removedBudget(existing)).toEqual({ id: existing.id, categoryId: 'a', monthlyLimitCents: 1000, deleted: true })
})
