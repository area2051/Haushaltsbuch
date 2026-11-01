import { describe, expect, test } from 'vitest'
import { hashPassword, verifyPassword } from '../src/auth/passwords.js'

describe('passwords', () => {
  test('hash is argon2id and verifies', async () => {
    const h = await hashPassword('geheim123')
    expect(h.startsWith('$argon2id$')).toBe(true)
    expect(await verifyPassword(h, 'geheim123')).toBe(true)
  })
  test('verifyPassword rejects wrong password', async () => {
    const h = await hashPassword('geheim123')
    expect(await verifyPassword(h, 'falsch')).toBe(false)
  })
  test('verifyPassword returns false on malformed hash', async () => {
    expect(await verifyPassword('garbage', 'x')).toBe(false)
  })
})
