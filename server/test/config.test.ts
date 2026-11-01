import { expect, test } from 'vitest'
import { loadConfig } from '../src/config.js'
import { todayIn } from '../src/clock.js'

test('rejects short JWT_SECRET', () => {
  expect(() => loadConfig({ DATABASE_URL: 'postgres://x', JWT_SECRET: 'short' })).toThrow(/JWT_SECRET/)
})
test('rejects missing DATABASE_URL', () => {
  expect(() => loadConfig({ JWT_SECRET: 'x'.repeat(32) })).toThrow(/DATABASE_URL/)
})
test('rejects invalid PORT', () => {
  expect(() => loadConfig({ DATABASE_URL: 'postgres://x', JWT_SECRET: 'x'.repeat(32), PORT: 'abc' })).toThrow(/PORT/)
})
test('applies defaults', () => {
  const c = loadConfig({ DATABASE_URL: 'postgres://x', JWT_SECRET: 'x'.repeat(32) })
  expect(c).toMatchObject({ port: 3000, timeZone: 'Europe/Berlin' })
})
test('reads explicit values', () => {
  const c = loadConfig({ DATABASE_URL: 'postgres://x', JWT_SECRET: 'y'.repeat(40), PORT: '8080', TZ: 'UTC' })
  expect(c).toEqual({ databaseUrl: 'postgres://x', jwtSecret: 'y'.repeat(40), port: 8080, timeZone: 'UTC' })
})
test('todayIn uses the given time zone', () => {
  const clock = { now: () => new Date('2026-01-31T23:30:00Z') }
  expect(todayIn(clock, 'Europe/Berlin')).toBe('2026-02-01')
})
