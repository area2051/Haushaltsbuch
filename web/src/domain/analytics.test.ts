import { describe, expect, test } from 'vitest'
import { budget, cat, tx } from '../test/fixtures'
import {
  budgetLevel,
  budgetProgress,
  categoryTrend,
  cumulativeDailyExpenses,
  expensesByCategory,
  expensesByPerson,
  monthlyTrend,
  rankCategories,
  summary,
} from './analytics'

test('summary only counts the given month', () => {
  const txs = [
    tx(1000, '2026-11-01', { kind: 'income' }),
    tx(500, '2026-11-30'),
    tx(50, '2026-11-15'),
    tx(9999, '2026-10-31'),
    tx(9999, '2026-12-01', { kind: 'income' }),
  ]
  expect(summary(txs, '2026-11')).toEqual({ incomeCents: 1000, expenseCents: 550, balanceCents: 450 })
  expect(summary([], '2026-11')).toEqual({ incomeCents: 0, expenseCents: 0, balanceCents: 0 })
})

test('expensesByCategory ignores income and sorts descending', () => {
  const txs = [
    tx(200, '2026-11-02', { categoryId: 'a' }),
    tx(500, '2026-11-03', { categoryId: 'b' }),
    tx(100, '2026-11-04', { categoryId: 'a' }),
    tx(9000, '2026-11-04', { categoryId: 'c', kind: 'income' }),
    tx(9000, '2026-10-04', { categoryId: 'c' }),
  ]
  expect(expensesByCategory(txs, '2026-11')).toEqual([
    { id: 'b', cents: 500 },
    { id: 'a', cents: 300 },
  ])
})

test('expensesByPerson groups by payer', () => {
  const txs = [
    tx(300, '2026-11-02', { paidBy: 'u2' }),
    tx(100, '2026-11-02', { paidBy: 'u1' }),
    tx(250, '2026-11-02', { paidBy: 'u1' }),
    tx(999, '2026-11-02', { paidBy: 'u2', kind: 'income' }),
  ]
  expect(expensesByPerson(txs, '2026-11')).toEqual([
    { id: 'u1', cents: 350 },
    { id: 'u2', cents: 300 },
  ])
})

describe('budgetLevel', () => {
  test.each([
    [0, 100, 'ok'],
    [79, 100, 'ok'],
    [80, 100, 'warning'],
    [99, 100, 'warning'],
    [100, 100, 'exceeded'],
    [150, 100, 'exceeded'],
    [0, 0, 'ok'],
    [1, 0, 'exceeded'],
  ] as const)('%i of %i → %s', (spent, limit, want) => expect(budgetLevel(spent, limit)).toBe(want))
})

test('budgetProgress uses the month expenses of the budget category', () => {
  const txs = [
    tx(300, '2026-11-02', { categoryId: 'food' }),
    tx(200, '2026-11-20', { categoryId: 'food' }),
    tx(700, '2026-10-20', { categoryId: 'food' }),
    tx(400, '2026-11-20', { categoryId: 'food', kind: 'income' }),
    tx(400, '2026-11-20', { categoryId: 'fun' }),
  ]
  const [p] = budgetProgress([budget('food', 1000)], txs, '2026-11')
  expect(p).toEqual({ categoryId: 'food', spentCents: 500, limitCents: 1000, ratio: 0.5, level: 'ok' })
})

test('rankCategories orders by use in the last 90 days, then sortOrder', () => {
  const a = cat('a', 'expense', { sortOrder: 0 })
  const b = cat('b', 'expense', { sortOrder: 1 })
  const c = cat('c', 'expense', { sortOrder: 2 })
  const d = cat('d', 'expense', { sortOrder: 3 })
  const txs = [
    tx(1, '2026-11-16', { categoryId: 'c' }),
    tx(1, '2026-08-19', { categoryId: 'c' }), // today - 89: inside
    tx(1, '2026-11-01', { categoryId: 'b' }),
    tx(1, '2026-08-18', { categoryId: 'd' }), // today - 90: outside
    tx(1, '2026-08-18', { categoryId: 'd' }),
    tx(1, '2026-11-17', { categoryId: 'd' }), // future: outside
  ]
  expect(rankCategories([d, c, b, a], txs, 'expense', '2026-11-16').map((x) => x.id)).toEqual(['c', 'b', 'a', 'd'])
})

test('rankCategories excludes archived categories and the other kind', () => {
  const cats = [cat('e1'), cat('e2', 'expense', { archived: true }), cat('i1', 'income')]
  expect(rankCategories(cats, [], 'expense', '2026-11-16').map((x) => x.id)).toEqual(['e1'])
  expect(rankCategories(cats, [], 'income', '2026-11-16').map((x) => x.id)).toEqual(['i1'])
})

test('monthlyTrend returns the last n months oldest first, including empty months', () => {
  const txs = [
    tx(1000, '2026-11-05', { kind: 'income' }),
    tx(300, '2026-11-06'),
    tx(200, '2026-09-30'),
    tx(5000, '2026-08-31'), // before the window
  ]
  expect(monthlyTrend(txs, '2026-11', 3)).toEqual([
    { month: '2026-09', incomeCents: 0, expenseCents: 200, balanceCents: -200 },
    { month: '2026-10', incomeCents: 0, expenseCents: 0, balanceCents: 0 },
    { month: '2026-11', incomeCents: 1000, expenseCents: 300, balanceCents: 700 },
  ])
})

test('cumulativeDailyExpenses accumulates expenses per day of month', () => {
  const txs = [
    tx(100, '2026-02-01'),
    tx(50, '2026-02-03'),
    tx(25, '2026-02-03'),
    tx(999, '2026-02-02', { kind: 'income' }),
    tx(999, '2026-03-01'),
  ]
  expect(cumulativeDailyExpenses(txs, '2026-02', 4)).toEqual([100, 100, 175, 175])
})

test('categoryTrend: top categories over the window, the rest as others, oldest month first', () => {
  const txs = [
    tx(500, '2026-10-02', { categoryId: 'a' }),
    tx(300, '2026-11-02', { categoryId: 'a' }),
    tx(400, '2026-11-02', { categoryId: 'b' }),
    tx(100, '2026-11-03', { categoryId: 'c' }),
    tx(50, '2026-09-30', { categoryId: 'c' }),
    tx(999, '2026-11-03', { categoryId: 'a', kind: 'income' }),
    tx(999, '2026-08-31', { categoryId: 'z' }), // before the window
  ]
  const t = categoryTrend(txs, '2026-11', 3, 2)
  expect(t.top).toEqual(['a', 'b'])
  expect(t.rows).toEqual([
    { month: '2026-09', a: 0, b: 0, others: 50 },
    { month: '2026-10', a: 500, b: 0, others: 0 },
    { month: '2026-11', a: 300, b: 400, others: 100 },
  ])
})
