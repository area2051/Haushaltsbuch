import { expect, test } from 'vitest'
import { cat, tx } from '../test/fixtures'
import { csvBlob, csvFileName, makeCsv } from './csv'

const HEADER = 'Datum;Art;Kategorie;Betrag;Notiz;Bezahlt von'
const cats = new Map([['food', cat('food', 'expense', { name: 'Lebensmittel' })], ['pay', cat('pay', 'income', { name: 'Gehalt' })]])
const members = new Map([['u1', 'Anna']])
const csv = (txs: ReturnType<typeof tx>[], from = '2026-01-01', to = '2026-12-31') => makeCsv(txs, cats, members, from, to)

test('empty export is the header line', () => {
  expect(csv([])).toBe(HEADER + '\r\n')
})

test('rows use German date, kind, category, decimal comma and payer', () => {
  const out = csv([
    tx(123456, '2026-02-01', { categoryId: 'pay', kind: 'income', paidBy: 'u1', note: 'Nov' }),
    tx(5, '2026-02-01', { categoryId: 'food', paidBy: 'u1' }),
  ])
  expect(out.split('\r\n')).toEqual([
    HEADER,
    '01.02.2026;Einnahme;Gehalt;1234,56;Nov;Anna',
    '01.02.2026;Ausgabe;Lebensmittel;0,05;;Anna',
    '',
  ])
})

test('rows are sorted by date and stable within a day', () => {
  const lines = csv([tx(3, '2026-03-02'), tx(1, '2026-03-01'), tx(2, '2026-03-02'), tx(4, '2026-03-01')]).split('\r\n')
  expect(lines.slice(1, 5).map((l) => l.split(';')[3])).toEqual(['0,01', '0,04', '0,03', '0,02'])
})

test('range is inclusive on both ends', () => {
  const lines = csv([tx(1, '2026-10-31'), tx(2, '2026-11-01'), tx(3, '2026-11-30'), tx(4, '2026-12-01')], '2026-11-01', '2026-11-30')
    .split('\r\n')
  expect(lines.slice(1, -1).map((l) => l.slice(0, 10))).toEqual(['01.11.2026', '30.11.2026'])
})

test('fields with separators, quotes or line breaks are quoted', () => {
  const out = csv([
    tx(1, '2026-01-01', { note: 'a;b' }),
    tx(1, '2026-01-02', { note: 'sag "hi"' }),
    tx(1, '2026-01-03', { note: 'zwei\nZeilen' }),
  ])
  expect(out).toContain(';"a;b";')
  expect(out).toContain(';"sag ""hi""";')
  expect(out).toContain(';"zwei\nZeilen";')
})

test('unknown category and payer stay empty', () => {
  expect(csv([tx(100, '2026-11-01', { categoryId: 'gone', paidBy: 'gone' })])).toContain('01.11.2026;Ausgabe;;1,00;;\r\n')
})

test('blob starts with a UTF-8 BOM', async () => {
  const bytes = new Uint8Array(await csvBlob('x').arrayBuffer())
  expect([...bytes]).toEqual([0xef, 0xbb, 0xbf, 0x78])
})

test('file name names the range', () => {
  expect(csvFileName('2026-11-01', '2026-11-30')).toBe('Haushaltsbuch_2026-11-01_2026-11-30.csv')
})
