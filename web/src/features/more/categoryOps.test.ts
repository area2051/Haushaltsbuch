import { expect, test } from 'vitest'
import { budget, cat, tx } from '../../test/fixtures'
import type { RecurringRule, Transaction } from '../../domain/types'
import { categoryNameProblem, moveBudgetEffect, moveCategory, newCategory, parentOptions, removalPlan, reorder } from './categoryOps'

const rule = (categoryId: string): RecurringRule => ({
  id: 'r1', amountCents: 100, kind: 'expense', categoryId, note: null, paidBy: 'u1', frequency: 'monthly', interval: 1,
  startDate: '2026-01-01', endDate: null, nextDueDate: '2026-12-01', deleted: false, version: 1,
})
const strip = <T extends { version: number }>({ version: _v, ...rest }: T) => rest

test('a used category is archived, nothing else changes', () => {
  const c = cat('food')
  const cases: Array<[Transaction[], RecurringRule[]]> = [[[tx(1, '2026-11-01', { categoryId: 'food' })], []], [[], [rule('food')]]]
  for (const [txs, rules] of cases) {
    const plan = removalPlan(c, txs, rules, [c])
    expect(plan.action).toBe('archive')
    expect(plan.action !== 'blocked' && plan.records).toEqual([{ table: 'categories', record: { ...strip(c), archived: true } }])
  }
})

test('an unused category is deleted alone; the server deletes its budget in the same transaction', () => {
  const c = cat('food')
  const plan = removalPlan(c, [tx(1, '2026-11-01', { categoryId: 'other' })], [rule('other')], [c])
  expect(plan.action).toBe('delete')
  // Sending the budget delete separately would lose the budget if the category delete is rejected.
  expect(plan.action !== 'blocked' && plan.records).toEqual([{ table: 'categories', record: { ...strip(c), deleted: true } }])
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
  expect(newCategory({ name: '  Haustier ', icon: 'pawprint', color: '#795548', kind: 'expense', parentId: null }, existing, 'id-1')).toEqual({
    id: 'id-1', name: 'Haustier', icon: 'pawprint', color: '#795548', kind: 'expense', sortOrder: 4, parentId: null, archived: false, deleted: false,
  })
  expect(newCategory({ name: 'X', icon: 'cart', color: '#000000', kind: 'income', parentId: null }, [], 'id-2').sortOrder).toBe(0)
})

test.each([
  ['', 'empty'],
  ['   ', 'empty'],
  ['x'.repeat(41), 'tooLong'],
  ['x'.repeat(40), null],
  ['  Essen  ', null],
] as const)('name %j → %s', (name, want) => expect(categoryNameProblem(name)).toBe(want))

test('a category with active children cannot be removed', () => {
  const parent = cat('home')
  const child = cat('power', 'expense', { parentId: 'home' })
  expect(removalPlan(parent, [], [], [parent, child])).toEqual({ action: 'blocked' })
  const gone = cat('power', 'expense', { parentId: 'home', deleted: true })
  expect(removalPlan(parent, [], [], [parent, gone]).action).toBe('delete')
})

test('new subcategory takes the parent color and goes last among its siblings', () => {
  const home = cat('home', 'expense', { color: '#112233', sortOrder: 7 })
  const a = cat('a', 'expense', { parentId: 'home', sortOrder: 3 })
  const b = cat('b', 'expense', { parentId: 'home', sortOrder: 4 })
  const created = newCategory({ name: ' Gas ', icon: 'flame', color: '#FFFFFF', kind: 'expense', parentId: 'home' }, [home, a, b], 'n1')
  expect(created).toMatchObject({ id: 'n1', name: 'Gas', color: '#112233', sortOrder: 5, parentId: 'home', kind: 'expense' })
  const first = newCategory({ name: 'X', icon: 'i', color: '#FFFFFF', kind: 'expense', parentId: 'home' }, [home], 'n2')
  expect(first.sortOrder).toBe(0)
})

test('new top-level category ignores subcategories when numbering', () => {
  const home = cat('home', 'expense', { sortOrder: 1 })
  const sub = cat('s', 'expense', { parentId: 'home', sortOrder: 9 })
  const created = newCategory({ name: 'Auto', icon: 'i', color: '#123456', kind: 'expense', parentId: null }, [home, sub], 'n')
  expect(created).toMatchObject({ sortOrder: 2, parentId: null, color: '#123456' })
})

test('moveCategory adopts the new parent color and goes last; moving to top level goes last among top-level', () => {
  const home = cat('home', 'expense', { color: '#112233', sortOrder: 1 })
  const kid = cat('kid', 'expense', { parentId: 'home', sortOrder: 4 })
  const food = cat('food', 'expense', { color: '#445566', sortOrder: 0 })
  const moved = moveCategory(food, 'home', [home, kid, food])
  expect(moved).toEqual({ ...strip(food), parentId: 'home', color: '#112233', sortOrder: 5 })
  const up = moveCategory(kid, null, [home, kid, food])
  expect(up).toEqual({ ...strip(kid), parentId: null, sortOrder: 2 })
})

test('moveBudgetEffect: none / moves / deleted', () => {
  const food = cat('food')
  const b = (id: string, deleted = false) => ({ ...budget(id, 100), deleted })
  expect(moveBudgetEffect(food, 'home', [])).toBe('none')
  expect(moveBudgetEffect(food, 'home', [b('food', true)])).toBe('none')
  expect(moveBudgetEffect(food, 'home', [b('food')])).toBe('moves')
  expect(moveBudgetEffect(food, 'home', [b('food'), b('home', true)])).toBe('moves')
  expect(moveBudgetEffect(food, 'home', [b('food'), b('home')])).toBe('deleted')
  expect(moveBudgetEffect(cat('kid', 'expense', { parentId: 'home' }), 'home', [b('kid'), b('home')])).toBe('none')
})

test('parentOptions: same-kind, active main categories other than c; none if c has children', () => {
  const a = cat('a'), b = cat('b'), inc = cat('inc', 'income'), old = cat('old', 'expense', { archived: true })
  const kid = cat('kid', 'expense', { parentId: 'a' })
  const all = [a, b, inc, old, kid]
  expect(parentOptions(b, all, 'expense').map((c) => c.id)).toEqual(['a'])
  expect(parentOptions(null, all, 'expense').map((c) => c.id)).toEqual(['a', 'b'])
  expect(parentOptions(a, all, 'expense')).toEqual([])
  expect(parentOptions(kid, all, 'expense').map((c) => c.id)).toEqual(['a', 'b'])
})
