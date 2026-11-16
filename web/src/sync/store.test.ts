import { beforeEach, expect, test } from 'vitest'
import { ApiError } from '../api/client'
import type { TransactionInput } from '../domain/types'
import { FakeSyncServer } from '../test/fakeSync'
import { SaveError, SyncStore } from './store'

let server: FakeSyncServer
let store: SyncStore

const txInput = (id: string, amountCents = 100, extra: Partial<TransactionInput> = {}): TransactionInput => ({
  id,
  amountCents,
  kind: 'expense',
  categoryId: 'c1',
  date: '2026-11-16',
  note: null,
  paidBy: 'u1',
  recurringRuleId: null,
  deleted: false,
  ...extra,
})

beforeEach(() => {
  server = new FakeSyncServer()
  store = new SyncStore(server)
})

const errorOf = (p: Promise<unknown>) => p.then(() => null, (e: unknown) => e)

test('first pull loads everything visible and remembers the version', async () => {
  server.put('transactions', txInput('t1'))
  server.put('transactions', txInput('t2', 200, { deleted: true }))
  server.put('users', { id: 'u1', username: 'anna', displayName: 'Anna', isAdmin: true, deleted: false })

  await store.pull()
  const s = store.getState()
  expect(s.loaded).toBe(true)
  expect([...s.transactions.keys()]).toEqual(['t1'])
  expect(s.users.get('u1')?.displayName).toBe('Anna')
  expect(server.requests[0]).toEqual({ lastVersion: 0, changes: {} })

  await store.pull()
  expect(server.requests[1]!.lastVersion).toBe(3)
})

test('later pulls apply updates and deletions', async () => {
  server.put('transactions', txInput('t1'))
  server.put('transactions', txInput('t2'))
  await store.pull()

  server.put('transactions', txInput('t1', 999))
  server.put('transactions', txInput('t2', 200, { deleted: true }))
  await store.pull()

  const txs = store.getState().transactions
  expect([...txs.keys()]).toEqual(['t1'])
  expect(txs.get('t1')?.amountCents).toBe(999)
})

test('a full resync replaces the local data', async () => {
  server.put('transactions', txInput('t1'))
  await store.pull()
  server.rows.transactions.clear()
  server.put('transactions', txInput('t9'))
  server.forceFullResync = true

  await store.pull()
  expect([...store.getState().transactions.keys()]).toEqual(['t9'])
})

test('save shows the change immediately and sends only that record', async () => {
  await store.pull()
  let resolve!: () => void
  server.gate = new Promise((r) => (resolve = r))

  const saving = store.save('transactions', txInput('t1', 1250))
  expect(store.getState().transactions.get('t1')?.amountCents).toBe(1250)

  resolve()
  await saving
  expect(server.requests.at(-1)).toEqual({ lastVersion: 0, changes: { transactions: [txInput('t1', 1250)] } })
  expect(store.getState().transactions.get('t1')?.version).toBe(1)
})

test('a rejected save is rolled back and reported with its reason', async () => {
  server.put('categories', { id: 'c1', name: 'Essen', icon: 'cart', color: '#4CAF50', kind: 'expense', sortOrder: 0, archived: false, deleted: false })
  await store.pull()
  server.rejectWhen = (table, r) => (table === 'categories' && r.deleted ? 'category_in_use' : null)

  const e = await errorOf(store.save('categories', { ...store.getState().categories.get('c1')!, deleted: true }))
  expect(e).toBeInstanceOf(SaveError)
  expect((e as SaveError).reason).toBe('category_in_use')
  expect(store.getState().categories.get('c1')?.name).toBe('Essen')
})

test('a rejected new record disappears again', async () => {
  await store.pull()
  server.rejectWhen = () => 'invalid_value'
  await errorOf(store.save('transactions', txInput('t1')))
  expect(store.getState().transactions.has('t1')).toBe(false)
})

test('a save that cannot reach the server is rolled back and marks the store offline', async () => {
  server.put('transactions', txInput('t1', 100))
  await store.pull()
  server.offline = true

  const e = await errorOf(store.save('transactions', txInput('t1', 500)))
  expect((e as ApiError).code).toBe('unreachable')
  expect(store.getState().transactions.get('t1')?.amountCents).toBe(100)
  expect(store.getState().online).toBe(false)

  server.offline = false
  await store.pull()
  expect(store.getState().online).toBe(true)
})

test('sync calls run one after another with the latest version', async () => {
  await store.pull()
  await Promise.all([store.save('transactions', txInput('t1')), store.save('transactions', txInput('t2')), store.pull()])
  expect(server.requests.map((r) => r.lastVersion)).toEqual([0, 0, 1, 2])
})

test('a pull answered while a save is pending does not hide the pending change', async () => {
  server.put('transactions', txInput('t1', 100))
  await store.pull()
  server.put('transactions', txInput('t1', 100, { note: 'vom Handy' })) // v2, comes back with the pull

  let resolve!: () => void
  server.gate = new Promise((r) => (resolve = r))
  const pulling = store.pull()
  const saving = store.save('transactions', txInput('t1', 777))
  resolve()
  await pulling
  expect(store.getState().transactions.get('t1')?.amountCents).toBe(777)
  await saving
  expect(store.getState().transactions.get('t1')?.amountCents).toBe(777)
})

test('subscribers are notified on changes', async () => {
  let calls = 0
  const unsubscribe = store.subscribe(() => calls++)
  await store.pull()
  expect(calls).toBeGreaterThan(0)
  unsubscribe()
  const before = calls
  await store.pull()
  expect(calls).toBe(before)
})

test('reset forgets all data', async () => {
  server.put('transactions', txInput('t1'))
  await store.pull()
  store.reset()
  expect(store.getState().transactions.size).toBe(0)
  expect(store.getState().loaded).toBe(false)
  await store.pull()
  expect(server.requests.at(-1)!.lastVersion).toBe(0)
})

const tick = () => new Promise((r) => setTimeout(r, 0))

test('an answer arriving after reset is ignored', async () => {
  server.put('transactions', txInput('t1'))
  let resolve!: () => void
  server.gate = new Promise((r) => (resolve = r))
  const pulling = store.pull()
  await tick()
  expect(server.requests).toHaveLength(1) // in flight
  store.reset()
  resolve()
  await pulling
  expect(store.getState().transactions.size).toBe(0)
  expect(store.getState().loaded).toBe(false)
})

test('saves queued before reset are not sent', async () => {
  let resolve!: () => void
  server.gate = new Promise((r) => (resolve = r))
  const pulling = store.pull()
  const saving = store.save('transactions', txInput('t1'))
  await tick()
  store.reset()
  resolve()
  await Promise.all([pulling, saving])
  expect(server.requests).toHaveLength(1) // only the pull that was already in flight
  expect(store.getState().transactions.size).toBe(0)
})

test('lastSyncAt is the time of the last successful answer', async () => {
  let now = new Date('2026-11-16T10:00:00Z')
  const timed = new SyncStore(server, () => now)
  expect(timed.getState().lastSyncAt).toBeNull()
  await timed.pull()
  expect(timed.getState().lastSyncAt).toEqual(new Date('2026-11-16T10:00:00Z'))
  now = new Date('2026-11-16T10:05:00Z')
  server.offline = true
  await timed.pull().catch(() => {})
  expect(timed.getState().lastSyncAt).toEqual(new Date('2026-11-16T10:00:00Z'))
})

test('removed members leave the member list but keep their name for old entries', async () => {
  server.put('users', { id: 'u2', username: 'ben', displayName: 'Ben', isAdmin: false, deleted: false })
  await store.pull()
  server.put('users', { id: 'u2', username: 'ben', displayName: 'Ben', isAdmin: false, deleted: true })
  await store.pull()
  expect(store.getState().users.has('u2')).toBe(false)
  expect(store.getState().names.get('u2')).toBe('Ben')
})

test('a new record sorts as newest until the server assigns its version', async () => {
  server.put('transactions', txInput('old'))
  await store.pull()
  let resolve!: () => void
  server.gate = new Promise((r) => (resolve = r))
  const saving = store.save('transactions', txInput('new'))
  const versions = store.getState().transactions
  expect(versions.get('new')!.version).toBeGreaterThan(versions.get('old')!.version)
  resolve()
  await saving
})

test('pending counts saves the server has not answered yet', async () => {
  await store.pull()
  let resolve!: () => void
  server.gate = new Promise((r) => (resolve = r))
  const a = store.save('transactions', txInput('a'))
  const b = store.save('transactions', txInput('b'))
  expect(store.getState().pending).toBe(2)
  resolve()
  await Promise.all([a, b])
  expect(store.getState().pending).toBe(0)
})
