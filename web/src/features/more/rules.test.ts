import { expect, test } from 'vitest'
import { RHYTHM_PRESETS, presetFor, ruleProblem, ruleSchedule, toRule } from './rules'

const draft = { cents: 4999, kind: 'expense' as const, categoryId: 'c1', paidBy: 'u1', note: ' Fitness ', frequency: 'monthly' as const, interval: 1, startDate: '2026-11-12', endDate: '' }

test('a draft becomes a rule record; blank end date is null', () => {
  expect(toRule(draft, 'r1')).toEqual({
    id: 'r1', amountCents: 4999, kind: 'expense', categoryId: 'c1', paidBy: 'u1', note: 'Fitness', frequency: 'monthly',
    interval: 1, startDate: '2026-11-12', endDate: null, deleted: false,
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
  [{ interval: 0 }, 'interval'],
  [{ interval: 25 }, 'interval'],
  [{ interval: 2.5 }, 'interval'],
] as const)('%o → %s', (patch, want) => expect(ruleProblem({ ...draft, ...patch })).toBe(want))

test('end date equal to start is fine', () => {
  expect(ruleProblem({ ...draft, endDate: draft.startDate })).toBeNull()
})

test('schedule text names the rhythm and follows the start date', () => {
  expect(ruleSchedule('weekly', 1, '2026-11-16')).toBe('Wöchentlich am Montag')
  expect(ruleSchedule('weekly', 2, '2026-11-16')).toBe('Alle 2 Wochen am Montag')
  expect(ruleSchedule('monthly', 1, '2026-11-03')).toBe('Monatlich am 3.')
  expect(ruleSchedule('monthly', 3, '2026-02-15')).toBe('Vierteljährlich am 15.')
  expect(ruleSchedule('monthly', 6, '2026-01-01')).toBe('Halbjährlich am 1.')
  expect(ruleSchedule('monthly', 4, '2026-01-03')).toBe('Alle 4 Monate am 3.')
  expect(ruleSchedule('monthly', 3, '2026-01-31')).toBe('Vierteljährlich am 31. (sonst Monatsletzter)')
  expect(ruleSchedule('yearly', 1, '2026-11-03')).toBe('Jährlich am 3. November')
  expect(ruleSchedule('yearly', 2, '2026-11-03')).toBe('Alle 2 Jahre am 3. November')
})

test('presets map to unit and interval, and back', () => {
  expect(RHYTHM_PRESETS.map((p) => [p.label, p.frequency, p.interval])).toEqual([
    ['Wöchentlich', 'weekly', 1],
    ['Alle 2 Wochen', 'weekly', 2],
    ['Monatlich', 'monthly', 1],
    ['Vierteljährlich', 'monthly', 3],
    ['Halbjährlich', 'monthly', 6],
    ['Jährlich', 'yearly', 1],
  ])
  expect(presetFor('monthly', 3)).toBe('quarterly')
  expect(presetFor('monthly', 4)).toBe('custom')
  expect(presetFor('weekly', 3)).toBe('custom')
})
