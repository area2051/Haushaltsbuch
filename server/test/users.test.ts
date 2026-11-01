import { eq } from 'drizzle-orm'
import { afterEach, beforeEach, describe, expect, test } from 'vitest'
import { refreshTokens, users } from '../src/db/schema.js'
import { createTestApp, login, setupAdmin } from './helpers.js'

type TestApp = Awaited<ReturnType<typeof createTestApp>>

describe('/me and /users', () => {
  let t: TestApp
  beforeEach(async () => {
    t = await createTestApp()
  })
  afterEach(async () => {
    await t.close()
  })

  const auth = (token: string) => ({ authorization: `Bearer ${token}` })

  async function createMember(adminToken: string, username = 'anna', password = 'passwort1') {
    const res = await t.app.inject({
      method: 'POST',
      url: '/users',
      headers: auth(adminToken),
      payload: { username, displayName: 'Anna', password },
    })
    expect(res.statusCode).toBe(201)
    return res.json() as { id: string; username: string; displayName: string; isAdmin: boolean }
  }

  test('GET /me returns current user', async () => {
    const admin = await setupAdmin(t.app)
    const { accessToken } = await login(t.app, 'admin', 'geheim123')
    const res = await t.app.inject({ method: 'GET', url: '/me', headers: auth(accessToken) })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toEqual(admin)
    expect((await t.app.inject({ method: 'GET', url: '/me' })).statusCode).toBe(401)
  })

  test('PATCH /me changes displayName and password only with correct current password', async () => {
    await setupAdmin(t.app)
    const { accessToken } = await login(t.app, 'admin', 'geheim123')

    const name = await t.app.inject({
      method: 'PATCH',
      url: '/me',
      headers: auth(accessToken),
      payload: { displayName: 'Neuer Name' },
    })
    expect(name.statusCode).toBe(200)
    expect(name.json().displayName).toBe('Neuer Name')

    for (const payload of [{ newPassword: 'neuespass1' }, { newPassword: 'neuespass1', currentPassword: 'falsch123' }]) {
      const bad = await t.app.inject({ method: 'PATCH', url: '/me', headers: auth(accessToken), payload })
      expect(bad.statusCode).toBe(400)
      expect(bad.json().error.code).toBe('wrong_password')
    }
    await login(t.app, 'admin', 'geheim123')

    const ok = await t.app.inject({
      method: 'PATCH',
      url: '/me',
      headers: auth(accessToken),
      payload: { currentPassword: 'geheim123', newPassword: 'neuespass1' },
    })
    expect(ok.statusCode).toBe(200)
    await login(t.app, 'admin', 'neuespass1')
    const old = await t.app.inject({
      method: 'POST',
      url: '/auth/login',
      payload: { username: 'admin', password: 'geheim123' },
    })
    expect(old.statusCode).toBe(401)
  })

  test('changing password revokes other refresh tokens', async () => {
    await setupAdmin(t.app)
    const a = await login(t.app, 'admin', 'geheim123')
    const b = await login(t.app, 'admin', 'geheim123')
    const res = await t.app.inject({
      method: 'PATCH',
      url: '/me',
      headers: auth(a.accessToken),
      payload: { currentPassword: 'geheim123', newPassword: 'neuespass1', keepRefreshToken: a.refreshToken },
    })
    expect(res.statusCode).toBe(200)
    const refresh = (refreshToken: string) =>
      t.app.inject({ method: 'POST', url: '/auth/refresh', payload: { refreshToken } })
    expect((await refresh(b.refreshToken)).statusCode).toBe(401)
    expect((await refresh(a.refreshToken)).statusCode).toBe(200)
  })

  test('changing password without keepRefreshToken revokes all refresh tokens', async () => {
    await setupAdmin(t.app)
    const a = await login(t.app, 'admin', 'geheim123')
    await t.app.inject({
      method: 'PATCH',
      url: '/me',
      headers: auth(a.accessToken),
      payload: { currentPassword: 'geheim123', newPassword: 'neuespass1' },
    })
    const r = await t.app.inject({ method: 'POST', url: '/auth/refresh', payload: { refreshToken: a.refreshToken } })
    expect(r.statusCode).toBe(401)
  })

  test('admin creates member who can log in', async () => {
    await setupAdmin(t.app)
    const admin = await login(t.app, 'admin', 'geheim123')
    const member = await createMember(admin.accessToken)
    expect(member).toMatchObject({ username: 'anna', displayName: 'Anna', isAdmin: false })
    const m = await login(t.app, 'anna', 'passwort1')
    const list = await t.app.inject({ method: 'GET', url: '/users', headers: auth(admin.accessToken) })
    expect(list.statusCode).toBe(200)
    expect(list.json().map((u: { username: string }) => u.username).sort()).toEqual(['admin', 'anna'])
    expect(m.accessToken).toBeTruthy()
  })

  test('duplicate username → 409 username_taken', async () => {
    await setupAdmin(t.app)
    const admin = await login(t.app, 'admin', 'geheim123')
    await createMember(admin.accessToken)
    const res = await t.app.inject({
      method: 'POST',
      url: '/users',
      headers: auth(admin.accessToken),
      payload: { username: 'anna', displayName: 'Zweite', password: 'passwort1' },
    })
    expect(res.statusCode).toBe(409)
    expect(res.json().error.code).toBe('username_taken')
  })

  test('removing admin from last admin → 409 last_admin', async () => {
    const adminUser = await setupAdmin(t.app)
    const admin = await login(t.app, 'admin', 'geheim123')
    const res = await t.app.inject({
      method: 'PATCH',
      url: `/users/${adminUser.id}`,
      headers: auth(admin.accessToken),
      payload: { isAdmin: false },
    })
    expect(res.statusCode).toBe(409)
    expect(res.json().error.code).toBe('last_admin')

    const member = await createMember(admin.accessToken)
    const promote = await t.app.inject({
      method: 'PATCH',
      url: `/users/${member.id}`,
      headers: auth(admin.accessToken),
      payload: { isAdmin: true },
    })
    expect(promote.statusCode).toBe(200)
    expect(promote.json().isAdmin).toBe(true)
    const demote = await t.app.inject({
      method: 'PATCH',
      url: `/users/${adminUser.id}`,
      headers: auth(admin.accessToken),
      payload: { isAdmin: false },
    })
    expect(demote.statusCode).toBe(200)
  })

  test('member cannot list or manage users (403)', async () => {
    await setupAdmin(t.app)
    const admin = await login(t.app, 'admin', 'geheim123')
    const member = await createMember(admin.accessToken)
    const m = await login(t.app, 'anna', 'passwort1')
    expect((await t.app.inject({ method: 'GET', url: '/users', headers: auth(m.accessToken) })).statusCode).toBe(403)
    expect(
      (
        await t.app.inject({
          method: 'POST',
          url: '/users',
          headers: auth(m.accessToken),
          payload: { username: 'bob', displayName: 'Bob', password: 'passwort1' },
        })
      ).statusCode,
    ).toBe(403)
    expect(
      (
        await t.app.inject({
          method: 'PATCH',
          url: `/users/${member.id}`,
          headers: auth(m.accessToken),
          payload: { displayName: 'x' },
        })
      ).statusCode,
    ).toBe(403)
    expect((await t.app.inject({ method: 'GET', url: '/users' })).statusCode).toBe(401)
  })

  test('user update bumps version and updated_at', async () => {
    await setupAdmin(t.app)
    const admin = await login(t.app, 'admin', 'geheim123')
    const member = await createMember(admin.accessToken)
    const [before] = await t.db.select().from(users).where(eq(users.id, member.id))
    t.clock.advance(1000)
    const res = await t.app.inject({
      method: 'PATCH',
      url: `/users/${member.id}`,
      headers: auth(admin.accessToken),
      payload: { displayName: 'Anna B.' },
    })
    expect(res.statusCode).toBe(200)
    expect(res.json().displayName).toBe('Anna B.')
    const [after] = await t.db.select().from(users).where(eq(users.id, member.id))
    expect(Number(after!.version)).toBeGreaterThan(Number(before!.version))
    expect(after!.updatedAt.getTime()).toBeGreaterThanOrEqual(before!.updatedAt.getTime())

    const me = await t.app.inject({
      method: 'PATCH',
      url: '/me',
      headers: auth((await login(t.app, 'anna', 'passwort1')).accessToken),
      payload: { displayName: 'Anna C.' },
    })
    const [afterMe] = await t.db.select().from(users).where(eq(users.id, member.id))
    expect(me.statusCode).toBe(200)
    expect(Number(afterMe!.version)).toBeGreaterThan(Number(after!.version))
  })

  test('admin password reset revokes tokens; unknown id → 404', async () => {
    await setupAdmin(t.app)
    const admin = await login(t.app, 'admin', 'geheim123')
    const member = await createMember(admin.accessToken)
    const m = await login(t.app, 'anna', 'passwort1')
    const res = await t.app.inject({
      method: 'PATCH',
      url: `/users/${member.id}`,
      headers: auth(admin.accessToken),
      payload: { password: 'resetpass1' },
    })
    expect(res.statusCode).toBe(200)
    await login(t.app, 'anna', 'resetpass1')
    const r = await t.app.inject({ method: 'POST', url: '/auth/refresh', payload: { refreshToken: m.refreshToken } })
    expect(r.statusCode).toBe(401)
    const nf = await t.app.inject({
      method: 'PATCH',
      url: '/users/00000000-0000-4000-8000-000000000000',
      headers: auth(admin.accessToken),
      payload: { displayName: 'x' },
    })
    expect(nf.statusCode).toBe(404)
    expect(nf.json().error.code).toBe('user_not_found')
  })
  test('admin deletes a member: login and refresh → 401, synced as deleted, hidden from GET /users', async () => {
    const adminUser = await setupAdmin(t.app)
    const admin = await login(t.app, 'admin', 'geheim123')
    const member = await createMember(admin.accessToken)
    const m = await login(t.app, 'anna', 'passwort1')
    const [before] = await t.db.select().from(users).where(eq(users.id, member.id))

    const res = await t.app.inject({
      method: 'PATCH',
      url: `/users/${member.id}`,
      headers: auth(admin.accessToken),
      payload: { deleted: true },
    })
    expect(res.statusCode, res.body).toBe(200)
    expect(res.json()).toEqual(member)

    const [after] = await t.db.select().from(users).where(eq(users.id, member.id))
    expect(after!.deleted).toBe(true)
    expect(Number(after!.version)).toBeGreaterThan(Number(before!.version))
    expect(await t.db.select().from(refreshTokens).where(eq(refreshTokens.userId, member.id))).toEqual([])

    const loginRes = await t.app.inject({
      method: 'POST',
      url: '/auth/login',
      payload: { username: 'anna', password: 'passwort1' },
    })
    expect(loginRes.statusCode).toBe(401)
    const refresh = await t.app.inject({ method: 'POST', url: '/auth/refresh', payload: { refreshToken: m.refreshToken } })
    expect(refresh.statusCode).toBe(401)

    const list = await t.app.inject({ method: 'GET', url: '/users', headers: auth(admin.accessToken) })
    expect(list.json().map((u: { id: string }) => u.id)).toEqual([adminUser.id])

    const sync = await t.app.inject({
      method: 'POST',
      url: '/sync',
      headers: auth(admin.accessToken),
      payload: { lastVersion: Number(before!.version), changes: {} },
    })
    expect(sync.statusCode).toBe(200)
    expect(sync.json().changes.users).toEqual([{ ...member, version: Number(after!.version), deleted: true }])

    // Already deleted → 404; deleted: false (undelete) is not supported.
    const again = await t.app.inject({
      method: 'PATCH',
      url: `/users/${member.id}`,
      headers: auth(admin.accessToken),
      payload: { deleted: true },
    })
    expect(again.statusCode).toBe(404)
  })

  test('deleted: false is a no-op on an active user', async () => {
    await setupAdmin(t.app)
    const admin = await login(t.app, 'admin', 'geheim123')
    const member = await createMember(admin.accessToken)
    const [before] = await t.db.select().from(users).where(eq(users.id, member.id))
    const res = await t.app.inject({
      method: 'PATCH',
      url: `/users/${member.id}`,
      headers: auth(admin.accessToken),
      payload: { deleted: false },
    })
    expect(res.statusCode).toBe(200)
    const [after] = await t.db.select().from(users).where(eq(users.id, member.id))
    expect(after!.deleted).toBe(false)
    expect(after!.version).toBe(before!.version)
  })

  test('admin cannot delete themselves; the last admin cannot be deleted', async () => {
    const adminUser = await setupAdmin(t.app)
    const admin = await login(t.app, 'admin', 'geheim123')
    const self = await t.app.inject({
      method: 'PATCH',
      url: `/users/${adminUser.id}`,
      headers: auth(admin.accessToken),
      payload: { deleted: true },
    })
    expect(self.statusCode).toBe(409)
    expect(self.json().error.code).toBe('cannot_delete_self')

    // Anna becomes admin and demotes the original admin, whose access token still claims admin
    // (no DB lookup per request) until it expires: that token must not delete the last admin.
    const member = await createMember(admin.accessToken)
    await t.app.inject({
      method: 'PATCH',
      url: `/users/${member.id}`,
      headers: auth(admin.accessToken),
      payload: { isAdmin: true },
    })
    const anna = await login(t.app, 'anna', 'passwort1')
    const demote = await t.app.inject({
      method: 'PATCH',
      url: `/users/${adminUser.id}`,
      headers: auth(anna.accessToken),
      payload: { isAdmin: false },
    })
    expect(demote.statusCode).toBe(200)
    const last = await t.app.inject({
      method: 'PATCH',
      url: `/users/${member.id}`,
      headers: auth(admin.accessToken),
      payload: { deleted: true },
    })
    expect(last.statusCode).toBe(409)
    expect(last.json().error.code).toBe('last_admin')
    const [row] = await t.db.select().from(users).where(eq(users.id, member.id))
    expect(row!.deleted).toBe(false)
  })
})
