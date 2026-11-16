import { expect, test } from 'vitest'
import { appendDigit, deleteLast } from './amountInput'

test('digits shift in from the right', () => {
  let c = 0
  for (const d of [1, 2, 5, 0]) c = appendDigit(c, d)
  expect(c).toBe(1250)
})

test('delete removes the last digit', () => {
  expect(deleteLast(1250)).toBe(125)
  expect(deleteLast(7)).toBe(0)
})

test('a tenth digit is ignored', () => {
  expect(appendDigit(999_999_999, 1)).toBe(999_999_999)
  expect(appendDigit(99_999_999, 9)).toBe(999_999_999)
})

test('non-digits are ignored', () => {
  expect(appendDigit(12, 10)).toBe(12)
  expect(appendDigit(12, -1)).toBe(12)
})
