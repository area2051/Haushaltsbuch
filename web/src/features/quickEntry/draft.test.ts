import { expect, test } from 'vitest'
import { draftProblem, toTransaction } from './draft'

const draft = { cents: 1250, kind: 'expense' as const, categoryId: 'c1', date: '2026-11-16', paidBy: 'u1', note: '' }

test('a draft becomes a new transaction record', () => {
  expect(toTransaction(draft, 'id-1')).toEqual({
    id: 'id-1',
    amountCents: 1250,
    kind: 'expense',
    categoryId: 'c1',
    date: '2026-11-16',
    paidBy: 'u1',
    note: null,
    recurringRuleId: null,
    deleted: false,
  })
})

test('notes are trimmed, blank notes are null', () => {
  expect(toTransaction({ ...draft, note: '  Bäcker  ' }, 'x').note).toBe('Bäcker')
  expect(toTransaction({ ...draft, note: ' \n ' }, 'x').note).toBeNull()
})

test('editing keeps the recurring rule link', () => {
  expect(toTransaction(draft, 'x', 'rule-1').recurringRuleId).toBe('rule-1')
})

test.each([
  [{ cents: 0 }, 'amount'],
  [{ categoryId: '' }, 'category'],
  [{ date: '2026-02-30' }, 'date'],
  [{ paidBy: '' }, 'paidBy'],
  [{ note: 'x'.repeat(201) }, 'note'],
] as const)('draft with %o has problem %s', (patch, want) => {
  expect(draftProblem({ ...draft, ...patch })).toBe(want)
})

test('a complete draft has no problem', () => {
  expect(draftProblem(draft)).toBeNull()
  expect(draftProblem({ ...draft, note: `  ${'x'.repeat(200)}  ` })).toBeNull()
})
