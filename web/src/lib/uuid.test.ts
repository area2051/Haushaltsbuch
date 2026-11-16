import { expect, test } from 'vitest'
import { uuidv4 } from './uuid'

test('produces RFC 4122 version 4 UUIDs from random bytes', () => {
  const bytes = new Uint8Array(16).fill(0xff)
  expect(uuidv4(() => bytes)).toBe('ffffffff-ffff-4fff-bfff-ffffffffffff')
  const zero = new Uint8Array(16)
  expect(uuidv4(() => zero)).toBe('00000000-0000-4000-8000-000000000000')
})

test('default source gives distinct ids', () => {
  const ids = new Set(Array.from({ length: 100 }, () => uuidv4()))
  expect(ids.size).toBe(100)
  for (const id of ids) expect(id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
})
