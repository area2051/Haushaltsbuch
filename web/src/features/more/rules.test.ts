import { expect, test } from 'vitest'
import { ruleProblem, ruleSchedule, toRule } from './rules'

const draft = { cents: 4999, kind: 'expense' as const, categoryId: 'c1', paidBy: 'u1', note: ' Fitness ', frequency: 'monthly' as const, startDate: '2026-11-12', endDate: '' }

test('a draft becomes a rule record; blank end date is null', () => {
  expect(toRule(draft, 'r1')).toEqual({
    id: 'r1', amountCents: 4999, kind: 'expense', categoryId: 'c1', paidBy: 'u1', note: 'Fitness', frequency: 'monthly',
    startDate: '2026-11-12', endDate: null, deleted: false,
  })
  expect(toRule({ ...draft, endDate: '2027-01-31', note: '' }, 'r1')).toMatchObject({ endDate: '2027-01-31', note: null })
})

test.each([
  [{ cents: 0 }, 'amount'],
  [{ categoryId: '' }, 'category'],
  [{ paidBy: '' }, 'paidBy'],
  [{ startDate: '1999-12-31' }, 'startDate'],
  [{ startDate: '2026-02-30' }, 'startDate'],
  [{ endDate: '2026-11-11' }, 'endDate'],
  [{ endDate: '2026-13-01' }, 'endDate'],
  [{ note: 'x'.repeat(201) }, 'note'],
] as const)('%o → %s', (patch, want) => expect(ruleProblem({ ...draft, ...patch })).toBe(want))

test('end date equal to start is fine', () => {
  expect(ruleProblem({ ...draft, endDate: draft.startDate })).toBeNull()
})

test('schedule text follows the start date', () => {
  expect(ruleSchedule('weekly', '2026-11-16')).toBe('Wöchentlich am Montag')
  expect(ruleSchedule('monthly', '2026-11-03')).toBe('Monatlich am 3.')
  expect(ruleSchedule('monthly', '2026-01-31')).toBe('Monatlich am 31. (sonst Monatsletzter)')
  expect(ruleSchedule('yearly', '2026-11-03')).toBe('Jährlich am 3. November')
})
