import { expect, test } from 'vitest'
import { categoryTree } from '../../domain/categoryTree'
import { cat, tx } from '../../test/fixtures'
import { emptyFilter, filterActive, sections } from './list'

const cats = categoryTree([
  cat('food', 'expense', { name: 'Lebensmittel' }),
  cat('cafe', 'expense', { name: 'Café' }),
  cat('home', 'expense', { name: 'Wohnen' }),
  cat('power', 'expense', { name: 'Strom', parentId: 'home' }),
  cat('rent', 'expense', { name: 'Miete', parentId: 'home' }),
])

const amounts = (s: ReturnType<typeof sections>) => s.map((x) => [x.day, x.items.map((t) => t.amountCents)])

test('groups by day, newest day first, newest entry first within a day', () => {
  const txs = [
    tx(1, '2026-11-02', { version: 1 }),
    tx(2, '2026-11-05', { version: 2 }),
    tx(3, '2026-11-02', { version: 5 }),
  ]
  expect(amounts(sections(txs, emptyFilter, cats))).toEqual([
    ['2026-11-05', [2]],
    ['2026-11-02', [3, 1]],
  ])
})

test('day net: income minus expenses', () => {
  const s = sections([tx(500, '2026-11-02'), tx(2000, '2026-11-02', { kind: 'income' })], emptyFilter, cats)
  expect(s[0]!.netCents).toBe(1500)
})

test('filters by kind, category, payer and month', () => {
  const txs = [
    tx(1, '2026-11-02', { categoryId: 'food', paidBy: 'u1' }),
    tx(2, '2026-11-02', { categoryId: 'cafe', paidBy: 'u2' }),
    tx(3, '2026-11-02', { categoryId: 'food', paidBy: 'u2', kind: 'income' }),
    tx(4, '2026-10-31', { categoryId: 'food', paidBy: 'u1' }),
  ]
  const only = (f: Partial<typeof emptyFilter>) => sections(txs, { ...emptyFilter, ...f }, cats).flatMap((s) => s.items.map((t) => t.amountCents)).sort()
  expect(only({ kind: 'income' })).toEqual([3])
  expect(only({ categoryId: 'food' })).toEqual([1, 3, 4])
  expect(only({ paidBy: 'u2' })).toEqual([2, 3])
  expect(only({ month: '2026-10' })).toEqual([4])
})

test('search matches note or category name, ignoring case and accents', () => {
  const txs = [tx(1, '2026-11-02', { note: 'Wochenmarkt' }), tx(2, '2026-11-02', { categoryId: 'cafe' }), tx(3, '2026-11-02', { note: null })]
  const hits = (q: string) => sections(txs, { ...emptyFilter, search: q }, cats).flatMap((s) => s.items.map((t) => t.amountCents)).sort()
  expect(hits('MARKT')).toEqual([1])
  expect(hits('cafe')).toEqual([2])
  expect(hits('  ')).toEqual([1, 2, 3])
})

test('filterActive ignores search and month', () => {
  expect(filterActive(emptyFilter)).toBe(false)
  expect(filterActive({ ...emptyFilter, search: 'x', month: '2026-11' })).toBe(false)
  expect(filterActive({ ...emptyFilter, paidBy: 'u1' })).toBe(true)
})

test('category filter: parent matches its children, a child only itself', () => {
  const txs = [tx(1, '2026-11-02', { categoryId: 'home' }), tx(2, '2026-11-02', { categoryId: 'power' }), tx(3, '2026-11-02', { categoryId: 'rent' }), tx(4, '2026-11-02', { categoryId: 'food' })]
  const only = (id: string) => sections(txs, { ...emptyFilter, categoryId: id }, cats).flatMap((s) => s.items.map((t) => t.amountCents)).sort()
  expect(only('home')).toEqual([1, 2, 3])
  expect(only('power')).toEqual([2])
})

test('search matches the label of a subcategory booking', () => {
  const txs = [tx(2, '2026-11-02', { categoryId: 'power' }), tx(4, '2026-11-02', { categoryId: 'food' })]
  const hits = sections(txs, { ...emptyFilter, search: 'strom' }, cats).flatMap((s) => s.items.map((t) => t.amountCents))
  expect(hits).toEqual([2])
})
