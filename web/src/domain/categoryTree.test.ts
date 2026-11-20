import { expect, test } from 'vitest'
import { cat } from '../test/fixtures'
import { categoryTree } from './categoryTree'

const tree = categoryTree([
  cat('home', 'expense', { name: 'Wohnen', sortOrder: 1 }),
  cat('power', 'expense', { name: 'Strom', parentId: 'home', sortOrder: 2 }),
  cat('rent', 'expense', { name: 'Miete', parentId: 'home', sortOrder: 2 }),
  cat('water', 'expense', { name: 'Wasser', parentId: 'home', sortOrder: 1 }),
  cat('old', 'expense', { name: 'Alt', archived: true }),
  cat('oldchild', 'expense', { name: 'Kind', parentId: 'old' }),
])

test('rootOf maps children to their parent; main and unknown ids to themselves', () => {
  expect(tree.rootOf('power')).toBe('home')
  expect(tree.rootOf('home')).toBe('home')
  expect(tree.rootOf('gone')).toBe('gone')
})

test('childrenOf is ordered by sortOrder, then name', () => {
  expect(tree.childrenOf('home').map((c) => c.id)).toEqual(['water', 'rent', 'power'])
  expect(tree.childrenOf('power')).toEqual([])
})

test('labelFor', () => {
  expect(tree.labelFor('power')).toBe('Wohnen · Strom')
  expect(tree.labelFor('home')).toBe('Wohnen')
  expect(tree.labelFor('gone')).toBe('Unbekannt')
})

test('isSelectable is false for archived categories and children of an archived parent', () => {
  expect(tree.isSelectable(tree.byId.get('home')!)).toBe(true)
  expect(tree.isSelectable(tree.byId.get('power')!)).toBe(true)
  expect(tree.isSelectable(tree.byId.get('old')!)).toBe(false)
  expect(tree.isSelectable(tree.byId.get('oldchild')!)).toBe(false)
})

test('colorFor is the main category colour, also for children, unknown ids give undefined', () => {
  const t = categoryTree([
    cat('home', 'expense', { color: '#111111' }),
    cat('power', 'expense', { parentId: 'home', color: '#222222' }),
  ])
  expect(t.colorFor('power')).toBe('#111111')
  expect(t.colorFor('home')).toBe('#111111')
  expect(t.colorFor('gone')).toBeUndefined()
})
