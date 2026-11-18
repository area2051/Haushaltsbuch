import { expect, test } from 'vitest'
import { CATEGORY_SYMBOLS, FALLBACK_ICON, iconFor } from './icons'

// The fixed symbol list of the iOS category editor (MoreModels.swift `CategoryForm.symbols`)
// plus the server's default categories. The web picker must offer exactly what iOS can show.
const IOS_PICKER = [
  'cart', 'basket', 'fork.knife', 'cup.and.saucer', 'house', 'bolt', 'drop', 'flame',
  'car', 'fuelpump', 'bus', 'tram', 'bicycle', 'airplane', 'cross.case', 'pills',
  'heart', 'figure.run', 'tshirt', 'scissors', 'gift', 'gamecontroller', 'film', 'music.note',
  'book', 'graduationcap', 'pawprint', 'leaf', 'wifi', 'iphone', 'wrench.and.screwdriver',
  'banknote', 'creditcard', 'eurosign', 'chart.line.uptrend.xyaxis', 'building.columns',
  'briefcase', 'person.2', 'ellipsis.circle',
]
const SERVER_DEFAULTS = ['cart', 'house', 'car', 'gamecontroller', 'cross.case', 'tshirt', 'repeat', 'ellipsis.circle', 'banknote', 'plus.circle']

test('the picker offers the iOS symbols in the iOS order', () => {
  expect(CATEGORY_SYMBOLS).toEqual(IOS_PICKER)
})

test('every picker and default symbol has its own icon', () => {
  for (const s of [...IOS_PICKER, ...SERVER_DEFAULTS]) expect(iconFor(s), s).not.toBe(FALLBACK_ICON)
})

test('unknown symbols fall back to a neutral icon', () => {
  expect(iconFor('something.new')).toBe(FALLBACK_ICON)
  expect(iconFor('constructor')).toBe(FALLBACK_ICON)
})
