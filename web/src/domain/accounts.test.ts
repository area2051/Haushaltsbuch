import { expect, test } from 'vitest'
import { passwordProblem, usernameProblem } from './accounts'

test.each([
  ['anna', null],
  ['a.b_c-1', null],
  ['ab', 'format'],
  ['x'.repeat(33), 'format'],
  ['Anna', 'format'],
  ['an na', 'format'],
  ['', 'empty'],
] as const)('username %j → %s', (u, want) => expect(usernameProblem(u)).toBe(want))

test('passwords need 8 characters and a matching confirmation', () => {
  expect(passwordProblem('', '')).toBe('empty')
  expect(passwordProblem('1234567', '1234567')).toBe('short')
  expect(passwordProblem('12345678', '12345679')).toBe('mismatch')
  expect(passwordProblem('12345678', '12345678')).toBeNull()
})
