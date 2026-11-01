import { describe, expect, test } from 'vitest'
import { dueDates, firstOccurrenceOnOrAfter, nextOccurrence } from '../src/recurring/dates.js'

describe('nextOccurrence', () => {
  test('monthly on 31st clamps to month end and returns to 31st', () => {
    expect(nextOccurrence('2026-01-31', 'monthly', '2026-01-31')).toBe('2026-02-28')
    expect(nextOccurrence('2026-01-31', 'monthly', '2026-02-28')).toBe('2026-03-31')
  })
  test('monthly in leap year February', () =>
    expect(nextOccurrence('2028-01-30', 'monthly', '2028-01-30')).toBe('2028-02-29'))
  test('monthly rolls over the year', () =>
    expect(nextOccurrence('2026-01-15', 'monthly', '2026-12-15')).toBe('2027-01-15'))
  test('yearly Feb 29 -> Feb 28 in non-leap year, back to 29 in leap year', () => {
    expect(nextOccurrence('2028-02-29', 'yearly', '2028-02-29')).toBe('2029-02-28')
    expect(nextOccurrence('2028-02-29', 'yearly', '2031-02-28')).toBe('2032-02-29')
  })
  test('weekly keeps weekday', () =>
    expect(nextOccurrence('2026-11-02', 'weekly', '2026-11-02')).toBe('2026-11-09'))
  test('weekly from a date between occurrences', () =>
    expect(nextOccurrence('2026-11-02', 'weekly', '2026-11-05')).toBe('2026-11-09'))
  test('after before start returns start', () =>
    expect(nextOccurrence('2026-11-02', 'monthly', '2026-01-01')).toBe('2026-11-02'))
})

describe('firstOccurrenceOnOrAfter', () => {
  test('monthly 31st lands on March 31', () =>
    expect(firstOccurrenceOnOrAfter('2026-01-31', 'monthly', '2026-03-01')).toBe('2026-03-31'))
  test('date that is itself an occurrence is returned', () =>
    expect(firstOccurrenceOnOrAfter('2026-01-31', 'monthly', '2026-02-28')).toBe('2026-02-28'))
  test('future start returns start', () =>
    expect(firstOccurrenceOnOrAfter('2027-05-10', 'weekly', '2026-11-01')).toBe('2027-05-10'))
  test('start equal to date returns start', () =>
    expect(firstOccurrenceOnOrAfter('2026-11-01', 'yearly', '2026-11-01')).toBe('2026-11-01'))
})

describe('dueDates', () => {
  test('catches up missed dates', () => {
    expect(
      dueDates({ startDate: '2026-08-01', frequency: 'monthly', nextDueDate: '2026-09-01', endDate: null }, '2026-11-01'),
    ).toEqual({ dates: ['2026-09-01', '2026-10-01', '2026-11-01'], nextDueDate: '2026-12-01' })
  })
  test('respects endDate', () => {
    expect(
      dueDates({ startDate: '2026-08-01', frequency: 'monthly', nextDueDate: '2026-09-01', endDate: '2026-10-15' }, '2026-11-01'),
    ).toEqual({ dates: ['2026-09-01', '2026-10-01'], nextDueDate: '2026-11-01' })
  })
  test('returns nothing before start / when nextDueDate is in the future', () => {
    expect(
      dueDates({ startDate: '2026-12-01', frequency: 'monthly', nextDueDate: '2026-12-01', endDate: null }, '2026-11-01'),
    ).toEqual({ dates: [], nextDueDate: '2026-12-01' })
  })
  test('uses anchored clamping while catching up', () => {
    expect(
      dueDates({ startDate: '2026-01-31', frequency: 'monthly', nextDueDate: '2026-02-28', endDate: null }, '2026-04-30'),
    ).toEqual({ dates: ['2026-02-28', '2026-03-31', '2026-04-30'], nextDueDate: '2026-05-31' })
  })
})
