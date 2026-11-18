import { expect, test } from 'vitest'
import { centsToInput, formatMoney, formatSigned, parseMoney } from './money'

// Intl uses a no-break space before €.
const nb = (s: string) => s.replace(/ /g, ' ')

test('formatMoney uses German grouping and decimal comma', () => {
  expect(formatMoney(123456)).toBe(nb('1.234,56 €'))
  expect(formatMoney(5)).toBe(nb('0,05 €'))
})

test('formatSigned prefixes income with + and expense with a real minus', () => {
  expect(formatSigned(1250, 'income')).toBe(nb('+12,50 €'))
  expect(formatSigned(1250, 'expense')).toBe(nb('−12,50 €'))
})

test.each([
  ['12,5', 1250],
  ['12,50 €', 1250],
  ['1.234,56', 123456],
  ['12.50', 1250],
  ['1.234', 123400],
  ['7', 700],
  ['0,01', 1],
])('parseMoney(%s) → %i', (s, want) => expect(parseMoney(s)).toBe(want))

test.each(['', '0', '0,00', '-5', 'abc', '1,234', '12,345', '10000000,00'])('parseMoney(%s) rejects', (s) =>
  expect(parseMoney(s)).toBeNull(),
)

test('centsToInput round-trips through parseMoney', () => {
  expect(centsToInput(1250)).toBe('12,50')
  expect(centsToInput(5)).toBe('0,05')
})
