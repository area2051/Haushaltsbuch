import { expect, test } from 'vitest'
import { cat, tx } from '../../test/fixtures'
import type { RecurringRule, Transaction } from '../../domain/types'
import { categoryNameProblem, newCategory, removalPlan, reorder } from './categoryOps'

const rule = (categoryId: string): RecurringRule => ({
  id: 'r1', amountCents: 100, kind: 'expense', categoryId, note: null, paidBy: 'u1', frequency: 'monthly', interval: 1,
  startDate: '2026-01-01', endDate: null, nextDueDate: '2026-12-01', deleted: false, version: 1,
})
const strip = <T extends { version: number }>({ version: _v, ...rest }: T) => rest

test('a used category is archived, nothing else changes', () => {
  const c = cat('food')
  const cases: Array<[Transaction[], RecurringRule[]]> = [[[tx(1, '2026-11-01', { categoryId: 'food' })], []], [[], [rule('food')]]]
  for (const [txs, rules] of cases) {
    const plan = removalPlan(c, txs, rules)
    expect(plan.action).toBe('archive')
    expect(plan.records).toEqual([{ table: 'categories', record: { ...strip(c), archived: true } }])
  }
})

test('an unused category is deleted alone; the server deletes its budget in the same transaction', () => {
  const c = cat('food')
  const plan = removalPlan(c, [tx(1, '2026-11-01', { categoryId: 'other' })], [rule('other')])
  expect(plan.action).toBe('delete')
  // Sending the budget delete separately would lose the budget if the category delete is rejected.
  expect(plan.records).toEqual([{ table: 'categories', record: { ...strip(c), deleted: true } }])
})

test('reorder numbers the given order 0…n-1 and returns only changed categories', () => {
  const a = cat('a', 'expense', { sortOrder: 0 })
  const b = cat('b', 'expense', { sortOrder: 1 })
  const c = cat('c', 'income', { sortOrder: 5 })
  expect(reorder([b, a, c])).toEqual([
    { ...strip(b), sortOrder: 0 },
    { ...strip(a), sortOrder: 1 },
    { ...strip(c), sortOrder: 2 },
  ])
  expect(reorder([a, b])).toEqual([])
})

test('a new category goes to the end of its kind with a trimmed name', () => {
  const existing = [cat('a', 'expense', { sortOrder: 3 }), cat('b', 'income', { sortOrder: 9 })]
  expect(newCategory({ name: '  Haustier ', icon: 'pawprint', color: '#795548', kind: 'expense' }, existing, 'id-1')).toEqual({
    id: 'id-1', name: 'Haustier', icon: 'pawprint', color: '#795548', kind: 'expense', sortOrder: 4, archived: false, deleted: false,
  })
  expect(newCategory({ name: 'X', icon: 'cart', color: '#000000', kind: 'income' }, [], 'id-2').sortOrder).toBe(0)
})

test.each([
  ['', 'empty'],
  ['   ', 'empty'],
  ['x'.repeat(41), 'tooLong'],
  ['x'.repeat(40), null],
  ['  Essen  ', null],
] as const)('name %j → %s', (name, want) => expect(categoryNameProblem(name)).toBe(want))
