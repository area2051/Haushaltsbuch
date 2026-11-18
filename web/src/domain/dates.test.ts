import { describe, expect, test } from 'vitest'
import { addDays, addMonths, dayHeading, firstDay, germanDate, isValidDay, lastDay, monthShort, monthTitle, today } from './dates'

describe('isValidDay', () => {
  test.each([
    ['2026-11-16', true],
    ['2024-02-29', true],
    ['2026-02-29', false],
    ['2026-13-01', false],
    ['2026-1-01', false],
    ['16.11.2026', false],
  ])('%s → %s', (s, want) => expect(isValidDay(s)).toBe(want))
})

test('today uses the local calendar date', () => {
  expect(today(new Date(2026, 0, 31, 23, 30))).toBe('2026-01-31')
})

test('addDays crosses month, year and leap day', () => {
  expect(addDays('2026-01-31', 1)).toBe('2026-02-01')
  expect(addDays('2026-01-01', -1)).toBe('2025-12-31')
  expect(addDays('2024-03-01', -1)).toBe('2024-02-29')
  expect(addDays('2026-11-16', -89)).toBe('2026-08-19')
})

test('addMonths wraps years in both directions', () => {
  expect(addMonths('2026-11', 2)).toBe('2027-01')
  expect(addMonths('2026-01', -1)).toBe('2025-12')
  expect(addMonths('2026-03', -14)).toBe('2025-01')
})

test('first and last day of month', () => {
  expect(firstDay('2026-02')).toBe('2026-02-01')
  expect(lastDay('2026-02')).toBe('2026-02-28')
  expect(lastDay('2024-02')).toBe('2024-02-29')
  expect(lastDay('2026-11')).toBe('2026-11-30')
})

test('german formats', () => {
  expect(monthTitle('2026-03')).toBe('März 2026')
  expect(germanDate('2026-02-01')).toBe('01.02.2026')
})

test('dayHeading names today and yesterday, adds the year only for other years', () => {
  expect(dayHeading('2026-11-16', '2026-11-16')).toBe('Heute')
  expect(dayHeading('2026-11-15', '2026-11-16')).toBe('Gestern')
  expect(dayHeading('2026-11-02', '2026-11-16')).toBe('Montag, 2. November')
  expect(dayHeading('2025-12-31', '2026-01-05')).toBe('Mittwoch, 31. Dezember 2025')
})

test('monthShort is the abbreviated month without dot', () => {
  expect(monthShort('2026-11')).toBe('Nov')
  expect(monthShort('2026-03')).toBe('Mär')
})
