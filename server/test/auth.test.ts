import { createHash } from 'node:crypto'
import { eq } from 'drizzle-orm'
import { decodeJwt } from 'jose'
import { afterEach, beforeEach, describe, expect, test } from 'vitest'
import { createLoginLimiter } from '../src/auth/loginLimiter.js'
import { pruneExpiredRefreshTokens } from '../src/auth/tokens.js'
import { hashPassword } from '../src/auth/passwords.js'
import { refreshTokens, users } from '../src/db/schema.js'
import { AppError } from '../src/errors.js'
import { createTestApp, MutableClock, setupAdmin } from './helpers.js'

let t: Awaited<ReturnType<typeof createTestApp>>

beforeEach(async () => {
  t = await createTestApp()
  // Test-only routes; must be registered before the first inject (app.ready()).
  t.app.get('/test/protected', { preHandler: t.app.authenticate }, async (req) => ({ user: req.user }))
  t.app.get('/test/admin', { preHandler: [t.app.authenticate, t.app.requireAdmin] }, async () => ({ ok: true }))
})
afterEach(async () => {
  await t.close()
})

const creds = { username: 'admin', password: 'geheim123' }

async function login(payload: Record<string, unknown> = creds) {
  return t.app.inject({ method: 'POST', url: '/auth/login', payload })
}

async function loginOk(payload: Record<string, unknown> = creds) {
  const res = await login(payload)
  expect(res.statusCode).toBe(200)
  return res.json() as { accessToken: string; refreshToken: string; user: { id: string; isAdmin: boolean } }
}

async function refresh(refreshToken: string) {
  return t.app.inject({ method: 'POST', url: '/auth/refresh', payload: { refreshToken } })
}

async function protectedGet(accessToken: string, url = '/test/protected') {
  return t.app.inject({ method: 'GET', url, headers: { authorization: `Bearer ${accessToken}` } })
}

async function createMember(username = 'member', password = 'geheim123') {
  const [u] = await t.db
    .insert(users)
    .values({ username, displayName: 'Member', passwordHash: await hashPassword(password), isAdmin: false })
    .returning()
  return u!
}

describe('POST /auth/login', () => {
  test('login returns tokens and user', async () => {
    const admin = await setupAdmin(t.app)
    const res = await login({ ...creds, deviceName: 'iPhone' })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.user).toEqual(admin)
    expect(body.user).not.toHaveProperty('passwordHash')
    expect(typeof body.accessToken).toBe('string')
    expect(body.refreshToken).toMatch(/^[A-Za-z0-9_-]{43}$/)

    const claims = decodeJwt(body.accessToken)
    expect(claims.sub).toBe(admin.id)
    expect(claims.admin).toBe(true)
    const nowSec = Math.floor(t.clock.now().getTime() / 1000)
    expect(claims.iat).toBe(nowSec)
    expect(claims.exp).toBe(nowSec + 15 * 60)

    const rows = await t.db.select().from(refreshTokens)
    expect(rows).toHaveLength(1)
    expect(rows[0]!.userId).toBe(admin.id)
    expect(rows[0]!.deviceName).toBe('iPhone')
    expect(rows[0]!.tokenHash).not.toBe(body.refreshToken)
    expect(rows[0]!.tokenHash).toBe(createHash('sha256').update(body.refreshToken).digest('hex'))
    expect(rows[0]!.expiresAt.getTime()).toBe(t.clock.now().getTime() + 90 * 24 * 60 * 60 * 1000)

    const me = await protectedGet(body.accessToken)
    expect(me.statusCode).toBe(200)
    expect(me.json()).toEqual({ user: { id: admin.id, isAdmin: true } })
  })

  test('wrong password → 401 invalid_credentials', async () => {
    await setupAdmin(t.app)
    const res = await login({ ...creds, password: 'falsch123' })
    expect(res.statusCode).toBe(401)
    expect(res.json()).toEqual({ error: { code: 'invalid_credentials', message: expect.any(String) } })
    expect(await t.db.select().from(refreshTokens)).toHaveLength(0)
  })

  test('unknown username → 401 invalid_credentials', async () => {
    await setupAdmin(t.app)
    const res = await login({ username: 'nobody', password: 'geheim123' })
    expect(res.statusCode).toBe(401)
    expect(res.json().error.code).toBe('invalid_credentials')
  })

  test('deleted user → 401 invalid_credentials', async () => {
    const admin = await setupAdmin(t.app)
    await t.db.update(users).set({ deleted: true }).where(eq(users.id, admin.id))
    const res = await login()
    expect(res.statusCode).toBe(401)
    expect(res.json().error.code).toBe('invalid_credentials')
  })

  test('6th attempt within a minute → 429, allowed again after 60s', async () => {
    await setupAdmin(t.app)
    for (let i = 0; i < 5; i++) {
      const res = await login({ ...creds, password: 'falsch123' })
      expect(res.statusCode).toBe(401)
    }
    // Locked even with the correct password.
    const locked = await login()
    expect(locked.statusCode).toBe(429)
    expect(locked.json().error.code).toBe('too_many_attempts')

    t.clock.advance(59_999)
    expect((await login()).statusCode).toBe(429)

    t.clock.advance(1)
    expect((await login()).statusCode).toBe(200)
  })

  test('parallel wrong-password logins cannot bypass the lockout', async () => {
    await setupAdmin(t.app)
    const results = await Promise.all(
      Array.from({ length: 10 }, () => login({ ...creds, password: 'falsch123' })),
    )
    const codes = results.map((r) => r.statusCode)
    expect(codes.filter((c) => c === 401).length).toBeLessThanOrEqual(5)
    expect(codes.filter((c) => c !== 401).every((c) => c === 429)).toBe(true)
    expect(codes.filter((c) => c === 429).length).toBeGreaterThanOrEqual(5)
    expect((await login()).statusCode).toBe(429)
  })

  test('lockout is per username', async () => {
    await setupAdmin(t.app)
    await createMember()
    for (let i = 0; i < 5; i++) await login({ ...creds, password: 'falsch123' })
    expect((await login()).statusCode).toBe(429)
    expect((await login({ username: 'member', password: 'geheim123' })).statusCode).toBe(200)
  })

  test('unknown usernames are locked out too', async () => {
    for (let i = 0; i < 5; i++) {
      expect((await login({ username: 'ghost', password: 'whatever1' })).statusCode).toBe(401)
    }
    expect((await login({ username: 'ghost', password: 'whatever1' })).statusCode).toBe(429)
  })

  test('successful login resets the failure counter', async () => {
    await setupAdmin(t.app)
    for (let i = 0; i < 4; i++) await login({ ...creds, password: 'falsch123' })
    expect((await login()).statusCode).toBe(200)
    for (let i = 0; i < 4; i++) {
      expect((await login({ ...creds, password: 'falsch123' })).statusCode).toBe(401)
    }
    expect((await login()).statusCode).toBe(200)
  })

  test('username is case-insensitive; the lockout counts all spellings together', async () => {
    await setupAdmin(t.app)
    expect((await login({ ...creds, username: 'Admin' })).statusCode).toBe(200)
    for (let i = 0; i < 5; i++) {
      expect((await login({ username: i % 2 ? 'ADMIN' : 'Admin', password: 'falsch123' })).statusCode).toBe(401)
    }
    expect((await login()).statusCode).toBe(429)
  })

  test('missing fields → 400 validation_failed', async () => {
    const res = await login({ username: 'admin' })
    expect(res.statusCode).toBe(400)
    expect(res.json().error.code).toBe('validation_failed')
  })
})

describe('access token / authenticate', () => {
  test('access token expires after 15 minutes', async () => {
    await setupAdmin(t.app)
    const { accessToken } = await loginOk()
    t.clock.advance(15 * 60_000 - 1000)
    expect((await protectedGet(accessToken)).statusCode).toBe(200)
    t.clock.advance(1000 + 1)
    const res = await protectedGet(accessToken)
    expect(res.statusCode).toBe(401)
    expect(res.json().error.code).toBe('unauthorized')
  })

  test('missing, malformed or forged token → 401 unauthorized', async () => {
    await setupAdmin(t.app)
    const { accessToken } = await loginOk()

    const none = await t.app.inject({ method: 'GET', url: '/test/protected' })
    expect(none.statusCode).toBe(401)
    expect(none.json().error.code).toBe('unauthorized')

    const basic = await t.app.inject({
      method: 'GET',
      url: '/test/protected',
      headers: { authorization: `Basic ${accessToken}` },
    })
    expect(basic.statusCode).toBe(401)

    expect((await protectedGet('not.a.jwt')).statusCode).toBe(401)

    const [h, p] = accessToken.split('.')
    expect((await protectedGet(`${h}.${p}.AAAA`)).statusCode).toBe(401)
  })

  test('refresh token is not accepted as access token', async () => {
    await setupAdmin(t.app)
    const { refreshToken } = await loginOk()
    expect((await protectedGet(refreshToken)).statusCode).toBe(401)
  })

  test('requireAdmin rejects non-admin with 403', async () => {
    await setupAdmin(t.app)
    await createMember()
    const admin = await loginOk()
    expect((await protectedGet(admin.accessToken, '/test/admin')).statusCode).toBe(200)

    const member = await loginOk({ username: 'member', password: 'geheim123' })
    expect(member.user.isAdmin).toBe(false)
    expect(decodeJwt(member.accessToken).admin).toBe(false)
    const res = await protectedGet(member.accessToken, '/test/admin')
    expect(res.statusCode).toBe(403)
    expect(res.json().error.code).toBe('forbidden')

    const anon = await t.app.inject({ method: 'GET', url: '/test/admin' })
    expect(anon.statusCode).toBe(401)
  })
})

describe('POST /auth/refresh', () => {
  test('refresh rotates: new token works, old token → 401', async () => {
    const admin = await setupAdmin(t.app)
    const first = await loginOk({ ...creds, deviceName: 'iPad' })
    t.clock.advance(60_000)

    const res = await refresh(first.refreshToken)
    expect(res.statusCode).toBe(200)
    const second = res.json()
    expect(Object.keys(second).sort()).toEqual(['accessToken', 'refreshToken'])
    expect(second.refreshToken).not.toBe(first.refreshToken)
    expect(decodeJwt(second.accessToken).sub).toBe(admin.id)
    expect((await protectedGet(second.accessToken)).statusCode).toBe(200)

    const rows = await t.db.select().from(refreshTokens)
    expect(rows).toHaveLength(1)
    expect(rows[0]!.deviceName).toBe('iPad')
    expect(rows[0]!.expiresAt.getTime()).toBe(t.clock.now().getTime() + 90 * 24 * 60 * 60 * 1000)

    const old = await refresh(first.refreshToken)
    expect(old.statusCode).toBe(401)
    expect(old.json().error.code).toBe('invalid_refresh_token')

    expect((await refresh(second.refreshToken)).statusCode).toBe(200)
  })

  test('reusing a rotated refresh token keeps the new one valid', async () => {
    await setupAdmin(t.app)
    const first = await loginOk()
    const second = (await refresh(first.refreshToken)).json()

    const replay = await refresh(first.refreshToken)
    expect(replay.statusCode).toBe(401)
    expect(replay.json().error.code).toBe('invalid_refresh_token')

    const third = await refresh(second.refreshToken)
    expect(third.statusCode).toBe(200)
  })

  test('concurrent refresh with the same token succeeds only once', async () => {
    await setupAdmin(t.app)
    const first = await loginOk()
    const results = await Promise.all([refresh(first.refreshToken), refresh(first.refreshToken)])
    expect(results.map((r) => r.statusCode).sort()).toEqual([200, 401])
    expect(await t.db.select().from(refreshTokens)).toHaveLength(1)
  })

  test('refresh token expires after 90 days', async () => {
    await setupAdmin(t.app)
    const a = await loginOk()
    const b = await loginOk()
    t.clock.advance(90 * 24 * 60 * 60_000 - 1)
    expect((await refresh(a.refreshToken)).statusCode).toBe(200)
    t.clock.advance(1)
    const res = await refresh(b.refreshToken)
    expect(res.statusCode).toBe(401)
    expect(res.json().error.code).toBe('invalid_refresh_token')
  })

  test('unknown refresh token → 401', async () => {
    const res = await refresh('A'.repeat(43))
    expect(res.statusCode).toBe(401)
    expect(res.json().error.code).toBe('invalid_refresh_token')
  })

  test('refresh for a deleted user → 401 invalid_refresh_token', async () => {
    const admin = await setupAdmin(t.app)
    const { refreshToken } = await loginOk()
    await t.db.update(users).set({ deleted: true }).where(eq(users.id, admin.id))
    const res = await refresh(refreshToken)
    expect(res.statusCode).toBe(401)
    expect(res.json().error.code).toBe('invalid_refresh_token')
  })

  test('refresh uses the current isAdmin from the database', async () => {
    const admin = await setupAdmin(t.app)
    const { refreshToken } = await loginOk()
    await t.db.update(users).set({ isAdmin: false }).where(eq(users.id, admin.id))
    const res = await refresh(refreshToken)
    expect(res.statusCode).toBe(200)
    expect(decodeJwt(res.json().accessToken).admin).toBe(false)
  })
})

describe('POST /auth/logout', () => {
  test('logout revokes the refresh token', async () => {
    await setupAdmin(t.app)
    const phone = await loginOk()
    const tablet = await loginOk()
    const res = await t.app.inject({
      method: 'POST',
      url: '/auth/logout',
      headers: { authorization: `Bearer ${phone.accessToken}` },
      payload: { refreshToken: phone.refreshToken },
    })
    expect(res.statusCode).toBe(204)
    expect(res.body).toBe('')
    const r = await refresh(phone.refreshToken)
    expect(r.statusCode).toBe(401)
    expect(r.json().error.code).toBe('invalid_refresh_token')
    // Other sessions are unaffected.
    expect((await refresh(tablet.refreshToken)).statusCode).toBe(200)
  })

  test('logout requires an access token', async () => {
    await setupAdmin(t.app)
    const { refreshToken } = await loginOk()
    const res = await t.app.inject({ method: 'POST', url: '/auth/logout', payload: { refreshToken } })
    expect(res.statusCode).toBe(401)
    expect(res.json().error.code).toBe('unauthorized')
    expect((await refresh(refreshToken)).statusCode).toBe(200)
  })

  test("logout cannot revoke another user's refresh token", async () => {
    await setupAdmin(t.app)
    await createMember()
    const admin = await loginOk()
    const member = await loginOk({ username: 'member', password: 'geheim123' })
    const res = await t.app.inject({
      method: 'POST',
      url: '/auth/logout',
      headers: { authorization: `Bearer ${member.accessToken}` },
      payload: { refreshToken: admin.refreshToken },
    })
    expect(res.statusCode).toBe(204)
    expect((await refresh(admin.refreshToken)).statusCode).toBe(200)
  })
})

describe('createLoginLimiter', () => {
  test('locks after 5 failures for 60 seconds', () => {
    const clock = new MutableClock('2026-01-15T12:00:00Z')
    const limiter = createLoginLimiter(clock)
    for (let i = 0; i < 5; i++) {
      expect(() => limiter.check('anna')).not.toThrow()
      limiter.fail('anna')
    }
    let err: unknown
    try {
      limiter.check('anna')
    } catch (e) {
      err = e
    }
    expect(err).toBeInstanceOf(AppError)
    expect((err as AppError).statusCode).toBe(429)
    expect((err as AppError).code).toBe('too_many_attempts')
    expect(() => limiter.check('ben')).not.toThrow()

    clock.advance(60_000)
    expect(() => limiter.check('anna')).not.toThrow()
    // Counter starts fresh after the lock expired.
    limiter.fail('anna')
    expect(() => limiter.check('anna')).not.toThrow()
  })

  test('attempts in flight count against the limit until settled', () => {
    const clock = new MutableClock('2026-01-15T12:00:00Z')
    const limiter = createLoginLimiter(clock)
    for (let i = 0; i < 5; i++) limiter.check('anna')
    expect(() => limiter.check('anna')).toThrow(AppError)
    limiter.release('anna')
    expect(() => limiter.check('anna')).not.toThrow()
    for (let i = 0; i < 3; i++) limiter.fail('anna')
    limiter.reset('anna')
    // One attempt still in flight; failures cleared by reset.
    for (let i = 0; i < 4; i++) limiter.check('anna')
    expect(() => limiter.check('anna')).toThrow(AppError)
  })

  test('reset clears failures', () => {
    const clock = new MutableClock('2026-01-15T12:00:00Z')
    const limiter = createLoginLimiter(clock)
    for (let i = 0; i < 5; i++) limiter.fail('anna')
    limiter.reset('anna')
    expect(() => limiter.check('anna')).not.toThrow()
  })

  test('failures older than the window do not accumulate', () => {
    const clock = new MutableClock('2026-01-15T12:00:00Z')
    const limiter = createLoginLimiter(clock)
    for (let i = 0; i < 4; i++) limiter.fail('anna')
    clock.advance(60_000)
    limiter.fail('anna')
    expect(() => limiter.check('anna')).not.toThrow()
  })
})

describe('pruneExpiredRefreshTokens', () => {
  test('deletes only expired refresh tokens', async () => {
    await setupAdmin(t.app)
    const { refreshToken: first } = await loginOk()
    t.clock.advance(24 * 60 * 60 * 1000)
    const { refreshToken: newer } = await loginOk()
    // First token expires exactly now (expires_at <= now counts as expired, like rotateRefreshToken).
    t.clock.advance(90 * 24 * 60 * 60 * 1000 - 24 * 60 * 60 * 1000)
    expect(await pruneExpiredRefreshTokens(t.db, t.clock.now())).toBe(1)
    const rows = await t.db.select().from(refreshTokens)
    expect(rows).toHaveLength(1)
    expect(rows[0]!.tokenHash).toBe(createHash('sha256').update(newer).digest('hex'))
    expect(first).not.toBe(newer)
    expect(await pruneExpiredRefreshTokens(t.db, t.clock.now())).toBe(0)
  })
})
