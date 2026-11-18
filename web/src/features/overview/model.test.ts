import { expect, test } from 'vitest'
import { budget, cat, tx } from '../../test/fixtures'
import { overviewModel } from './model'

const M = '2026-11'

test('donut shows the six largest categories and groups the rest as Weitere', () => {
  const cats = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'].map((id) => cat(id, 'expense', { name: id.toUpperCase(), color: '#111111' }))
  const txs = cats.map((c, i) => tx(800 - i * 100, '2026-11-02', { categoryId: c.id }))
  const m = overviewModel({ txs, categories: cats, members: [], budgets: [], month: M })
  expect(m.slices.map((s) => [s.name, s.cents])).toEqual([
    ['A', 800], ['B', 700], ['C', 600], ['D', 500], ['E', 400], ['F', 300], ['Weitere', 300],
  ])
})

test('unknown categories and payers are labelled Unbekannt', () => {
  const m = overviewModel({ txs: [tx(100, '2026-11-02', { categoryId: 'gone', paidBy: 'gone' })], categories: [], members: [], budgets: [], month: M })
  expect(m.slices[0]!.name).toBe('Unbekannt')
  expect(m.people[0]!.name).toBe('Unbekannt')
})

test('budget warnings: only active categories, only warning or exceeded, highest ratio first', () => {
  const categories = [cat('food'), cat('fun'), cat('old', 'expense', { archived: true }), cat('ok')]
  const txs = [
    tx(850, '2026-11-02', { categoryId: 'food' }), // 85 %
    tx(1200, '2026-11-02', { categoryId: 'fun' }), // 120 %
    tx(5000, '2026-11-02', { categoryId: 'old' }),
    tx(100, '2026-11-02', { categoryId: 'ok' }), // 10 %
    tx(5000, '2026-11-02', { categoryId: 'deleted' }),
  ]
  const budgets = [budget('food', 1000), budget('fun', 1000), budget('old', 1000), budget('ok', 1000), budget('deleted', 1000)]
  const m = overviewModel({ txs, categories, members: [], budgets, month: M })
  expect(m.warnings.map((w) => [w.categoryId, w.level])).toEqual([
    ['fun', 'exceeded'],
    ['food', 'warning'],
  ])
})

test('recent: five newest of the month, newest day first, newest entry first within a day', () => {
  const txs = [
    tx(1, '2026-11-03', { version: 1 }),
    tx(2, '2026-11-05', { version: 2 }),
    tx(3, '2026-11-05', { version: 7 }),
    tx(4, '2026-11-01', { version: 3 }),
    tx(5, '2026-11-04', { version: 4 }),
    tx(6, '2026-11-02', { version: 5 }),
    tx(7, '2026-12-01', { version: 6 }),
  ]
  const m = overviewModel({ txs, categories: [], members: [], budgets: [], month: M })
  expect(m.recent.map((t) => t.amountCents)).toEqual([3, 2, 5, 1, 6])
  expect(m.hasTransactions).toBe(true)
  expect(overviewModel({ txs, categories: [], members: [], budgets: [], month: '2026-10' }).hasTransactions).toBe(false)
})

test('budgets lists every active budget, fullest first', () => {
  const categories = [cat('food'), cat('fun'), cat('old', 'expense', { archived: true })]
  const txs = [tx(100, '2026-11-02', { categoryId: 'food' }), tx(500, '2026-11-02', { categoryId: 'fun' })]
  const budgets = [budget('food', 1000), budget('fun', 1000), budget('old', 1000)]
  const m = overviewModel({ txs, categories, members: [], budgets, month: M })
  expect(m.budgets.map((b) => [b.categoryId, b.ratio])).toEqual([
    ['fun', 0.5],
    ['food', 0.1],
  ])
})
