import { sql } from 'drizzle-orm'

/**
 * Keys for transaction-scoped Postgres advisory locks (`pg_advisory_xact_lock`).
 * Every key must be unique across the app; never reuse a number for a different purpose.
 *
 * Rule: every write that assigns a sync version (`nextval('sync_version_seq')`, explicitly or via
 * the column default) must hold LOCK_SYNC in its transaction, so versions become visible in commit
 * order and a sync never returns a `currentVersion` past a still-uncommitted lower version.
 * Lock order: LOCK_SETUP / LOCK_USERS first, LOCK_SYNC last, never the reverse (no deadlocks).
 */
export const LOCK_SETUP = 1
/** Serializes sync pushes/pulls so versions become visible in commit order. */
export const LOCK_SYNC = 2
/** Serializes admin-flag changes (last-admin check). */
export const LOCK_USERS = 3

type Executor = { execute(query: ReturnType<typeof sql>): PromiseLike<unknown> }

/** Takes the advisory lock `key` until the surrounding transaction ends. */
export async function lock(tx: Executor, key: number): Promise<void> {
  await tx.execute(sql`SELECT pg_advisory_xact_lock(${key})`)
}
