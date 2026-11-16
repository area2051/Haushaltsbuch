import { expect, test } from 'vitest'
import { exportRange } from './exportRange'

const today = '2026-11-16'

test.each([
  ['thisMonth', { from: '2026-11-01', to: '2026-11-30' }],
  ['lastMonth', { from: '2026-10-01', to: '2026-10-31' }],
  ['thisYear', { from: '2026-01-01', to: '2026-12-31' }],
] as const)('%s', (period, want) => expect(exportRange(period, today)).toEqual(want))

test('last month of January is December of last year', () => {
  expect(exportRange('lastMonth', '2026-01-10')).toEqual({ from: '2025-12-01', to: '2025-12-31' })
})

test('custom range must be valid and ordered', () => {
  expect(exportRange('custom', today, '2026-03-01', '2026-03-31')).toEqual({ from: '2026-03-01', to: '2026-03-31' })
  expect(exportRange('custom', today, '2026-03-31', '2026-03-01')).toBeNull()
  expect(exportRange('custom', today, '', '2026-03-01')).toBeNull()
})
