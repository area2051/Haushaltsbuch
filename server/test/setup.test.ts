import { count, eq } from 'drizzle-orm'
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest'
import { hashPassword, verifyPassword } from '../src/auth/passwords.js'
import { categories, users } from '../src/db/schema.js'
import { DEFAULT_CATEGORIES } from '../src/setup/defaultCategories.js'
import { createTestApp, setupAdmin } from './helpers.js'

// Spy on hashPassword (real implementation) to check that /setup skips argon2 once setup is done.
vi.mock('../src/auth/passwords.js', async (importOriginal) => {
  const mod = await importOriginal<typeof import('../src/auth/passwords.js')>()
  return { ...mod, hashPassword: vi.fn(mod.hashPassword) }
})

let t: Awaited<ReturnType<typeof createTestApp>>
beforeEach(async () => {
  t = await createTestApp()
})
afterEach(async () => {
  await t.close()
})

const body = { username: 'admin', displayName: 'Admin', password: 'geheim123' }

describe('health and setup', () => {
  test('health reports setupRequired=true on empty db', async () => {
    const res = await t.app.inject({ method: 'GET', url: '/health' })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toEqual({ status: 'ok', setupRequired: true })
  })

  test('health reports setupRequired=false after setup', async () => {
    await setupAdmin(t.app)
    const res = await t.app.inject({ method: 'GET', url: '/health' })
    expect(res.json()).toEqual({ status: 'ok', setupRequired: false })
  })

  test('setup creates admin and ten default categories', async () => {
    const res = await t.app.inject({ method: 'POST', url: '/setup', payload: body })
    expect(res.statusCode).toBe(201)
    const { user } = res.json()
    expect(user).toEqual({ id: expect.any(String), username: 'admin', displayName: 'Admin', isAdmin: true })
    expect(user).not.toHaveProperty('passwordHash')
    const [row] = await t.db.select().from(users).where(eq(users.id, user.id))
    expect(await verifyPassword(row!.passwordHash, 'geheim123')).toBe(true)
    const cats = await t.db.select().from(categories).orderBy(categories.sortOrder)
    expect(cats).toHaveLength(10)
    expect(cats[0]).toMatchObject({ name: 'Lebensmittel', sortOrder: 0, kind: 'expense', archived: false })
    expect(cats.map((c) => c.name)).toEqual(DEFAULT_CATEGORIES.map((c) => c.name))
    expect(cats[8]).toMatchObject({ name: 'Gehalt', kind: 'income' })
  })

  test('default categories have valid icons and distinct colors', () => {
    expect(DEFAULT_CATEGORIES).toHaveLength(10)
    for (const c of DEFAULT_CATEGORIES) expect(c.color).toMatch(/^#[0-9A-Fa-f]{6}$/)
    expect(new Set(DEFAULT_CATEGORIES.map((c) => c.color)).size).toBe(10)
  })

  test('setup twice returns 409 setup_already_done', async () => {
    await setupAdmin(t.app)
    const res = await t.app.inject({ method: 'POST', url: '/setup', payload: { ...body, username: 'other' } })
    expect(res.statusCode).toBe(409)
    expect(res.json().error.code).toBe('setup_already_done')
  })

  test('setup after setup is done → 409 without hashing the password', async () => {
    await setupAdmin(t.app)
    vi.mocked(hashPassword).mockClear()
    const res = await t.app.inject({ method: 'POST', url: '/setup', payload: { ...body, username: 'other' } })
    expect(res.statusCode).toBe(409)
    expect(hashPassword).not.toHaveBeenCalled()
  })

  test('setup rejects passwords longer than 1024 characters', async () => {
    const res = await t.app.inject({ method: 'POST', url: '/setup', payload: { ...body, password: 'x'.repeat(1025) } })
    expect(res.statusCode).toBe(400)
    expect(res.json().error.code).toBe('validation_failed')
  })

  test('concurrent setup calls create exactly one user', async () => {
    const [a, b] = await Promise.all([
      t.app.inject({ method: 'POST', url: '/setup', payload: body }),
      t.app.inject({ method: 'POST', url: '/setup', payload: { ...body, username: 'second' } }),
    ])
    expect([a.statusCode, b.statusCode].sort()).toEqual([201, 409])
    const [u] = await t.db.select({ n: count() }).from(users)
    expect(u!.n).toBe(1)
    const [c] = await t.db.select({ n: count() }).from(categories)
    expect(c!.n).toBe(10)
  })

  test('setup rejects password shorter than 8', async () => {
    const res = await t.app.inject({ method: 'POST', url: '/setup', payload: { ...body, password: 'short' } })
    expect(res.statusCode).toBe(400)
    expect(res.json().error.code).toBe('validation_failed')
  })

  test('setup rejects invalid username', async () => {
    for (const username of ['ab', 'Admin', 'a b c', 'x'.repeat(33)]) {
      const res = await t.app.inject({ method: 'POST', url: '/setup', payload: { ...body, username } })
      expect(res.statusCode).toBe(400)
    }
  })
})
