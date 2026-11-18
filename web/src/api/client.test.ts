import { beforeEach, expect, test, vi } from 'vitest'
import { FakeServer, memoryTokenStore } from '../test/fakeServer'
import { ApiClient, ApiError } from './client'

let server: FakeServer
let store: ReturnType<typeof memoryTokenStore>
let expired: ReturnType<typeof vi.fn<() => void>>
let api: ApiClient

beforeEach(() => {
  server = new FakeServer()
  store = memoryTokenStore()
  expired = vi.fn<() => void>()
  api = new ApiClient({ fetch: server.fetch, tokens: store, deviceName: 'Web (Test)', onSessionExpired: expired })
})

const errorOf = (p: Promise<unknown>) => p.then(() => null, (e: unknown) => e)

test('login keeps the refresh token and sends the access token afterwards', async () => {
  const user = await api.login('anna', 'geheim123')
  expect(user.username).toBe('anna')
  expect(store.get()).toBe('r1')
  expect(server.requests[0]!.body).toEqual({ username: 'anna', password: 'geheim123', deviceName: 'Web (Test)' })

  await api.me()
  expect(server.requests.at(-1)).toMatchObject({ path: '/me', auth: 'Bearer a1' })
})

test('wrong password is an ApiError with the server code and stores nothing', async () => {
  const e = await errorOf(api.login('anna', 'falsch'))
  expect(e).toBeInstanceOf(ApiError)
  expect((e as ApiError).code).toBe('invalid_credentials')
  expect((e as ApiError).status).toBe(401)
  expect(store.get()).toBeNull()
})

test('an expired access token is refreshed once and the request retried', async () => {
  await api.login('anna', 'geheim123')
  server.expireAccessTokens()

  const me = await api.me()
  expect(me.username).toBe('anna')
  expect(server.requests.map((r) => r.path)).toEqual(['/auth/login', '/me', '/auth/refresh', '/me'])
  expect(server.requests.at(-1)!.auth).toBe('Bearer a2')
  expect(store.get()).toBe('r2') // rotated
})

test('concurrent requests share one refresh', async () => {
  await api.login('anna', 'geheim123')
  server.expireAccessTokens()
  server.refreshDelayMs = 10

  await Promise.all([api.me(), api.me(), api.me()])
  expect(server.requests.filter((r) => r.path === '/auth/refresh')).toHaveLength(1)
})

test('a stored refresh token restores the session without logging in', async () => {
  const { refreshToken } = server.issue()
  store.set(refreshToken)
  expect(api.hasSession()).toBe(true)

  await api.me()
  expect(server.requests.map((r) => r.path)).toEqual(['/auth/refresh', '/me'])
})

test('a rejected refresh ends the session', async () => {
  store.set('revoked')
  const e = await errorOf(api.me())
  expect((e as ApiError).code).toBe('unauthorized')
  expect(store.get()).toBeNull()
  expect(api.hasSession()).toBe(false)
  expect(expired).toHaveBeenCalledOnce()
})

test('other errors keep the session', async () => {
  await api.login('anna', 'geheim123')
  const e = await errorOf(api.users())
  expect((e as ApiError).code).toBe('forbidden')
  expect(store.get()).toBe('r1')
  expect(expired).not.toHaveBeenCalled()
})

test('network failures become code unreachable and keep the session', async () => {
  await api.login('anna', 'geheim123')
  server.offline = true
  const e = await errorOf(api.me())
  expect((e as ApiError).code).toBe('unreachable')
  expect(store.get()).toBe('r1')
})

test('logout revokes the refresh token and clears the session even when offline', async () => {
  await api.login('anna', 'geheim123')
  await api.logout()
  expect(server.requests.at(-1)).toMatchObject({ path: '/auth/logout', body: { refreshToken: 'r1' } })
  expect(server.validRefresh.has('r1')).toBe(false)
  expect(api.hasSession()).toBe(false)

  await api.login('anna', 'geheim123')
  server.offline = true
  await api.logout()
  expect(store.get()).toBeNull()
})

test('changing the password asks the server to keep this device logged in', async () => {
  await api.login('anna', 'geheim123')
  await api.updateMe({ currentPassword: 'geheim123', newPassword: 'neuesPasswort' })
  expect(server.requests.at(-1)).toMatchObject({
    method: 'PATCH',
    path: '/me',
    body: { currentPassword: 'geheim123', newPassword: 'neuesPasswort', keepRefreshToken: 'r1' },
  })

  await api.updateMe({ displayName: 'Anni' })
  expect(server.requests.at(-1)!.body).toEqual({ displayName: 'Anni' })
})

test('logout with an expired access token revokes the rotated refresh token', async () => {
  await api.login('anna', 'geheim123')
  server.expireAccessTokens()
  await api.logout()
  // Refresh rotated r1 → r2; r2 must be the one revoked, so no session stays valid on the server.
  expect(server.revoked).toEqual(['r2'])
  expect(server.validRefresh.size).toBe(0)
})

test('password change with an expired access token keeps the rotated refresh token', async () => {
  await api.login('anna', 'geheim123')
  server.expireAccessTokens()
  await api.updateMe({ currentPassword: 'geheim123', newPassword: 'neuesPasswort' })
  expect(server.requests.at(-1)!.body).toMatchObject({ keepRefreshToken: 'r2' })
})
