import { describe, expect, test } from 'vitest'
import { dbRejectionReason } from '../src/sync/service.js'

describe('dbRejectionReason', () => {
  test('maps constraint and data-exception SQLSTATEs, also when wrapped by drizzle', () => {
    expect(dbRejectionReason({ code: '23503' })).toBe('foreign_key_violation')
    expect(dbRejectionReason({ code: '23505' })).toBe('unique_violation')
    expect(dbRejectionReason({ code: '23514' })).toBe('check_violation')
    expect(dbRejectionReason({ cause: { code: '22021' } })).toBe('invalid_value')
    expect(dbRejectionReason({ cause: { code: '22008' } })).toBe('invalid_value')
  })

  test('other errors are not mapped (→ rethrown, 500)', () => {
    expect(dbRejectionReason({ code: '40P01' })).toBeUndefined()
    expect(dbRejectionReason(new Error('boom'))).toBeUndefined()
  })
})
