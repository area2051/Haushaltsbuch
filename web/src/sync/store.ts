import type { components } from '../api/schema'
import type { Budget, Category, Member, RecurringRule, SyncInput, SyncTable, Transaction } from '../domain/types'

type S = components['schemas']

export type SyncApi = { sync(req: S['SyncRequest']): Promise<S['SyncResponse']> }

/** A record the server rejected; `reason` is `rejected[].reason`. */
export class SaveError extends Error {
  constructor(readonly reason: string) {
    super(reason)
    this.name = 'SaveError'
  }
}

type Out = {
  categories: Category
  transactions: Transaction
  budgets: Budget
  recurringRules: RecurringRule
}

export type SyncState = {
  /** True after the first successful pull. */
  loaded: boolean
  /** False after a request failed to reach the server, true again after the next success. */
  online: boolean
  /** Time of the last successful sync answer. */
  lastSyncAt: Date | null
  categories: Map<string, Category>
  transactions: Map<string, Transaction>
  budgets: Map<string, Budget>
  recurringRules: Map<string, RecurringRule>
  users: Map<string, Member>
  /** Display names of all members ever synced, including removed ones (for old entries, CSV). */
  names: Map<string, string>
  /** Saves the server has not answered yet. */
  pending: number
}

const TABLES: SyncTable[] = ['categories', 'transactions', 'budgets', 'recurringRules']

type Base = { [T in SyncTable]: Map<string, Out[T]> } & { users: Map<string, Member>; names: Map<string, string> }

const emptyBase = (): Base => ({
  categories: new Map(),
  transactions: new Map(),
  budgets: new Map(),
  recurringRules: new Map(),
  users: new Map(),
  names: new Map(),
})

type Pending = { table: SyncTable; record: SyncInput[SyncTable]; token: number }

/**
 * Online-only data store for the web app, fed by `POST /sync`.
 *
 * - `base` mirrors the server (non-deleted rows only).
 * - `pending` holds optimistic saves until the server answered, so a pull answered in between
 *   cannot hide them. The visible state is base + pending.
 * - All sync requests run one after another so each uses the version of the previous answer.
 */
export class SyncStore {
  private base = emptyBase()
  private pending = new Map<string, Pending>()
  private lastVersion = 0
  private loaded = false
  private online = true
  private lastSyncAt: Date | null = null
  private queue: Promise<unknown> = Promise.resolve()
  private nextToken = 0
  private generation = 0
  private listeners = new Set<() => void>()
  private state: SyncState

  constructor(
    private readonly api: SyncApi,
    private readonly now: () => Date = () => new Date(),
  ) {
    this.state = this.compute()
  }

  getState = (): SyncState => this.state

  subscribe = (fn: () => void): (() => void) => {
    this.listeners.add(fn)
    return () => this.listeners.delete(fn)
  }

  /** Fetches all changes since the last pull. */
  pull(): Promise<void> {
    return this.enqueue(async (generation) => {
      await this.request({}, generation)
    })
  }

  /** Saves one record: visible at once, rolled back if the server rejects it or is unreachable. */
  save<T extends SyncTable>(table: T, record: SyncInput[T]): Promise<void> {
    const key = `${table}:${record.id}`
    const token = ++this.nextToken
    this.pending.set(key, { table, record, token })
    this.emit()

    return this.enqueue(async (generation) => {
      try {
        const res = await this.request({ [table]: [record] }, generation)
        const rejection = res.rejected.find((r) => r.table === table && r.id === record.id)
        if (rejection) throw new SaveError(rejection.reason)
      } finally {
        if (this.pending.get(key)?.token === token) this.pending.delete(key)
        this.emit()
      }
    })
  }

  /** Forgets everything (logout). Requests still in flight are ignored. */
  reset(): void {
    this.generation++
    this.base = emptyBase()
    this.pending.clear()
    this.lastVersion = 0
    this.loaded = false
    this.online = true
    this.lastSyncAt = null
    this.emit()
  }

  /**
   * Runs `job` after all earlier jobs. The generation is fixed at enqueue time, so jobs queued
   * before a `reset()` neither send (no data of the old session goes out) nor apply anything.
   */
  private enqueue(job: (generation: number) => Promise<void>): Promise<void> {
    const generation = this.generation
    const guarded = () => (generation === this.generation ? job(generation) : Promise.resolve())
    const run = this.queue.then(guarded, guarded)
    this.queue = run.catch(() => {})
    return run
  }

  private async request(changes: S['SyncRequest']['changes'], generation: number): Promise<S['SyncResponse']> {
    let res: S['SyncResponse']
    try {
      res = await this.api.sync({ lastVersion: this.lastVersion, changes })
    } catch (e) {
      if ((e as { code?: string }).code === 'unreachable' && generation === this.generation) {
        this.online = false
        this.emit()
      }
      throw e
    }
    if (generation !== this.generation) return res
    this.apply(res)
    return res
  }

  private apply(res: S['SyncResponse']): void {
    if (res.fullResync) this.base = emptyBase()
    for (const table of TABLES) {
      const map = this.base[table] as Map<string, { deleted: boolean }>
      for (const row of res.changes[table] as Array<{ id: string; deleted: boolean }>) {
        if (row.deleted) map.delete(row.id)
        else map.set(row.id, row)
      }
    }
    for (const u of res.changes.users) {
      this.base.names.set(u.id, u.displayName)
      if (u.deleted) this.base.users.delete(u.id)
      else this.base.users.set(u.id, u)
    }
    this.lastVersion = res.currentVersion
    this.loaded = true
    this.online = true
    this.lastSyncAt = this.now()
    this.emit()
  }

  private compute(): SyncState {
    const view = {
      categories: new Map(this.base.categories),
      transactions: new Map(this.base.transactions),
      budgets: new Map(this.base.budgets),
      recurringRules: new Map(this.base.recurringRules),
    }
    for (const { table, record } of this.pending.values()) {
      const map = view[table] as Map<string, unknown>
      if (record.deleted) {
        map.delete(record.id)
        continue
      }
      const prev = map.get(record.id) as { version?: number; nextDueDate?: string } | undefined
      // A new record has no version yet; treat it as the newest so lists show it on top.
      const optimistic: Record<string, unknown> = { ...record, version: prev?.version ?? Number.MAX_SAFE_INTEGER }
      // Only the server computes the next due date; keep the known one meanwhile.
      if (table === 'recurringRules') optimistic.nextDueDate = prev?.nextDueDate ?? (record as SyncInput['recurringRules']).startDate
      map.set(record.id, optimistic)
    }
    return { loaded: this.loaded, online: this.online, lastSyncAt: this.lastSyncAt, ...view, users: new Map(this.base.users), names: new Map(this.base.names), pending: this.pending.size }
  }

  private emit(): void {
    this.state = this.compute()
    for (const fn of this.listeners) fn()
  }
}
