import { beforeEach, expect, test } from 'vitest'
import { ApiClient } from '../api/client'
import { FakeServer, memoryTokenStore } from '../test/fakeServer'
import { bootstrap } from './bootstrap'

let server: FakeServer
const client = (refresh: string | null = null) =>
  new ApiClient({ fetch: server.fetch, tokens: memoryTokenStore(refresh), deviceName: 'Web' })

beforeEach(() => {
  server = new FakeServer()
})

test('a valid stored session opens the app', async () => {
  const { refreshToken } = server.issue()
  expect(await bootstrap(client(refreshToken))).toEqual({ screen: 'ready', user: server.user })
})

test('an expired stored session asks for login', async () => {
  expect(await bootstrap(client('revoked'))).toEqual({ screen: 'login' })
})

test('without a session a fresh server asks for setup', async () => {
  server.setupRequired = true
  expect(await bootstrap(client())).toEqual({ screen: 'setup' })
})

test('without a session a set-up server asks for login', async () => {
  expect(await bootstrap(client())).toEqual({ screen: 'login' })
})

test('an unreachable server is reported, with or without session', async () => {
  server.offline = true
  expect(await bootstrap(client())).toEqual({ screen: 'unreachable' })
  expect(await bootstrap(client('r1'))).toEqual({ screen: 'unreachable' })
})
