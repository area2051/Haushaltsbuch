import type { components } from '../api/schema'
import { ApiError } from '../api/client'

type S = components['schemas']
type Table = 'categories' | 'transactions' | 'budgets' | 'recurringRules' | 'users'
type Row = { id: string; version: number } & Record<string, unknown>

/**
 * In-memory version of the server's sync semantics (docs spec §4): every write gets the next
 * version, the response contains all rows with version > lastVersion, and records matching
 * `rejectWhen` are rejected individually. `fullResync` is returned when asked to.
 */
export class FakeSyncServer {
  version = 0
  rows: Record<Table, Map<string, Row>> = {
    categories: new Map(),
    transactions: new Map(),
    budgets: new Map(),
    recurringRules: new Map(),
    users: new Map(),
  }
  requests: S['SyncRequest'][] = []
  rejectWhen: ((table: string, record: Record<string, unknown>) => string | null) | null = null
  offline = false
  forceFullResync = false
  /** Resolves pending responses manually when set (to interleave requests). */
  gate: Promise<void> | null = null

  put(table: Table, record: Record<string, unknown>): Row {
    const row = { ...record, version: ++this.version } as Row
    if (table === 'recurringRules' && !row.nextDueDate) row.nextDueDate = row.startDate
    this.rows[table].set(row.id, row)
    return row
  }

  sync = async (req: S['SyncRequest']): Promise<S['SyncResponse']> => {
    this.requests.push(structuredClone(req))
    if (this.gate) await this.gate
    if (this.offline) throw new ApiError(0, 'unreachable')
    const rejected: S['RejectedRecord'][] = []
    for (const [table, records] of Object.entries(req.changes) as [Table, Record<string, unknown>[]][]) {
      for (const r of records ?? []) {
        const reason = this.rejectWhen?.(table, r)
        if (reason) rejected.push({ table, id: r.id as string, reason })
        else this.put(table, r)
      }
    }
    const full = this.forceFullResync
    const since = full ? 0 : req.lastVersion
    const pick = (t: Table) => [...this.rows[t].values()].filter((r) => r.version > since) as never[]
    return {
      currentVersion: this.version,
      fullResync: full,
      rejected,
      changes: {
        categories: pick('categories'),
        transactions: pick('transactions'),
        budgets: pick('budgets'),
        recurringRules: pick('recurringRules'),
        users: pick('users'),
      },
    }
  }
}
