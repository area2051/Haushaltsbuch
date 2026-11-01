import { and, asc, eq, gt, sql } from 'drizzle-orm'
import type { z } from 'zod'
import type { Db } from '../db/client.js'
import { LOCK_SYNC, lock } from '../db/locks.js'
import { budgets, categories, recurringRules, transactions, users } from '../db/schema.js'
import { firstOccurrenceOnOrAfter } from '../recurring/dates.js'
import {
  type BudgetRecord,
  budgetRecord,
  type CategoryRecord,
  categoryRecord,
  type RecurringRuleRecord,
  recurringRuleRecord,
  type SyncChanges,
  type SyncRequest,
  type SyncResponse,
  type TransactionRecord,
  transactionRecord,
} from './schemas.js'

/** A transaction or savepoint handle (both expose the same query API). */
type Tx = Parameters<Parameters<Db['transaction']>[0]>[0]

type TableName = 'categories' | 'transactions' | 'budgets' | 'recurringRules'
type Rejected = SyncResponse['rejected'][number]

/** Thrown inside a record's savepoint to reject that record (rolls back the savepoint). */
class Rejection extends Error {
  constructor(readonly reason: string) {
    super(reason)
  }
}

const bump = () => ({ version: sql`nextval('sync_version_seq')`, updatedAt: sql`now()` })

/** Postgres SQLSTATE of an error, also when wrapped by drizzle (`cause`). */
function pgCode(e: unknown): string | undefined {
  let cur: unknown = e
  for (let i = 0; i < 5 && cur && typeof cur === 'object'; i++) {
    const code = (cur as { code?: unknown }).code
    if (typeof code === 'string' && /^[0-9A-Z]{5}$/.test(code)) return code
    cur = (cur as { cause?: unknown }).cause
  }
  return undefined
}

const DB_REASONS: Record<string, string> = {
  '23503': 'foreign_key_violation',
  '23505': 'unique_violation',
  '23514': 'check_violation',
}

/**
 * Per-record rejection reason for a DB error, or undefined if the error must abort the request.
 * Constraint violations and data exceptions (SQLSTATE class 22) are caused by the record itself;
 * rejecting just that record keeps one bad record from poisoning every retry of the push.
 */
export function dbRejectionReason(e: unknown): string | undefined {
  const code = pgCode(e)
  if (!code) return undefined
  return DB_REASONS[code] ?? (code.startsWith('22') ? 'invalid_value' : undefined)
}

function rawId(raw: unknown): string | null {
  if (raw && typeof raw === 'object' && typeof (raw as { id?: unknown }).id === 'string') {
    return (raw as { id: string }).id
  }
  return null
}

class Collector {
  readonly rejected: Rejected[] = []

  parse<T>(table: TableName, raw: unknown, schema: z.ZodType<T>): T | undefined {
    const res = schema.safeParse(raw)
    if (res.success) return res.data
    const issue = res.error.issues[0]
    const path = issue?.path.length ? `${issue.path.join('.')}: ` : ''
    this.rejected.push({ table, id: rawId(raw), reason: `${path}${issue?.message ?? 'invalid record'}` })
    return undefined
  }

  /** Runs `write` in its own savepoint; a rejection or constraint violation rolls back only this record. */
  async write(tx: Tx, table: TableName, id: string, write: (sp: Tx) => Promise<void>): Promise<boolean> {
    try {
      await tx.transaction(write)
      return true
    } catch (e) {
      const reason = e instanceof Rejection ? e.reason : dbRejectionReason(e)
      if (!reason) throw e
      this.rejected.push({ table, id, reason })
      return false
    }
  }
}

/**
 * A deleted category that receives a non-deleted transaction/rule/budget (another device was
 * offline) is restored as archived, with a new version so every device sees it again.
 */
async function reviveCategory(sp: Tx, categoryId: string): Promise<void> {
  await sp
    .update(categories)
    .set({ deleted: false, archived: true, ...bump() })
    .where(and(eq(categories.id, categoryId), eq(categories.deleted, true)))
}

/**
 * `paidBy` must not newly point at a deleted user. Unknown ids are left to the foreign key
 * (→ foreign_key_violation). Deleting a record, or keeping the paidBy it already has, stays
 * allowed so history of a removed member can still be edited or deleted.
 */
async function checkPaidBy(
  sp: Tx,
  rec: { deleted: boolean; paidBy: string },
  existingPaidBy: string | undefined,
): Promise<void> {
  if (rec.deleted || existingPaidBy === rec.paidBy) return
  const [u] = await sp.select({ deleted: users.deleted }).from(users).where(eq(users.id, rec.paidBy))
  if (u?.deleted) throw new Rejection('unknown_user')
}

async function upsertCategory(sp: Tx, r: CategoryRecord): Promise<void> {
  if (r.deleted) {
    const [txn] = await sp
      .select({ id: transactions.id })
      .from(transactions)
      .where(and(eq(transactions.categoryId, r.id), eq(transactions.deleted, false)))
      .limit(1)
    const [rule] = await sp
      .select({ id: recurringRules.id })
      .from(recurringRules)
      .where(and(eq(recurringRules.categoryId, r.id), eq(recurringRules.deleted, false)))
      .limit(1)
    if (txn || rule) throw new Rejection('category_in_use')
  }
  const { id: _id, ...fields } = r
  await sp
    .insert(categories)
    .values(r)
    .onConflictDoUpdate({ target: categories.id, set: { ...fields, ...bump() } })
  if (r.deleted) {
    // Budgets of a deleted category are meaningless; delete them in the same savepoint.
    await sp
      .update(budgets)
      .set({ deleted: true, ...bump() })
      .where(and(eq(budgets.categoryId, r.id), eq(budgets.deleted, false)))
  }
}

async function upsertRecurringRule(sp: Tx, r: RecurringRuleRecord, today: string): Promise<void> {
  const [existing] = await sp
    .select({
      startDate: recurringRules.startDate,
      frequency: recurringRules.frequency,
      nextDueDate: recurringRules.nextDueDate,
      paidBy: recurringRules.paidBy,
    })
    .from(recurringRules)
    .where(eq(recurringRules.id, r.id))
  await checkPaidBy(sp, r, existing?.paidBy)
  if (!r.deleted) await reviveCategory(sp, r.categoryId)

  let nextDueDate: string
  if (!existing) nextDueDate = r.startDate
  else if (existing.startDate !== r.startDate || existing.frequency !== r.frequency) {
    nextDueDate = firstOccurrenceOnOrAfter(r.startDate, r.frequency, today)
  } else nextDueDate = existing.nextDueDate

  const { id: _id, ...fields } = r
  await sp
    .insert(recurringRules)
    .values({ ...r, nextDueDate })
    .onConflictDoUpdate({ target: recurringRules.id, set: { ...fields, nextDueDate, ...bump() } })
}

async function upsertTransaction(sp: Tx, r: TransactionRecord): Promise<void> {
  const [existing] = await sp
    .select({ paidBy: transactions.paidBy })
    .from(transactions)
    .where(eq(transactions.id, r.id))
  await checkPaidBy(sp, r, existing?.paidBy)
  if (!r.deleted) await reviveCategory(sp, r.categoryId)
  const { id: _id, ...fields } = r
  await sp
    .insert(transactions)
    .values(r)
    .onConflictDoUpdate({ target: transactions.id, set: { ...fields, ...bump() } })
}

async function upsertBudget(sp: Tx, r: BudgetRecord): Promise<void> {
  if (!r.deleted) await reviveCategory(sp, r.categoryId)
  const { id: _id, ...fields } = r
  await sp
    .insert(budgets)
    .values(r)
    .onConflictDoUpdate({ target: budgets.id, set: { ...fields, ...bump() } })
}

/** Highest version across all sync tables (0 when empty). */
async function maxVersion(tx: Tx): Promise<number> {
  const rows = await tx.execute<{ v: string | null }>(sql`
    SELECT GREATEST(
      (SELECT max(version) FROM users),
      (SELECT max(version) FROM categories),
      (SELECT max(version) FROM transactions),
      (SELECT max(version) FROM budgets),
      (SELECT max(version) FROM recurring_rules)
    )::text AS v`)
  return Number(rows[0]?.v ?? 0)
}

/**
 * All records of all sync tables with `version > sinceVersion` (including deleted ones) and the
 * current highest version. Call inside a transaction holding LOCK_SYNC.
 */
export async function pull(
  tx: Tx,
  sinceVersion: number,
): Promise<{ currentVersion: number; changes: SyncChanges }> {
  const [cats, txns, buds, rules, us] = await Promise.all([
    tx
      .select({
        id: categories.id,
        version: categories.version,
        deleted: categories.deleted,
        name: categories.name,
        icon: categories.icon,
        color: categories.color,
        kind: categories.kind,
        sortOrder: categories.sortOrder,
        archived: categories.archived,
      })
      .from(categories)
      .where(gt(categories.version, sinceVersion))
      .orderBy(asc(categories.version)),
    tx
      .select({
        id: transactions.id,
        version: transactions.version,
        deleted: transactions.deleted,
        amountCents: transactions.amountCents,
        kind: transactions.kind,
        categoryId: transactions.categoryId,
        date: transactions.date,
        note: transactions.note,
        paidBy: transactions.paidBy,
        recurringRuleId: transactions.recurringRuleId,
      })
      .from(transactions)
      .where(gt(transactions.version, sinceVersion))
      .orderBy(asc(transactions.version)),
    tx
      .select({
        id: budgets.id,
        version: budgets.version,
        deleted: budgets.deleted,
        categoryId: budgets.categoryId,
        monthlyLimitCents: budgets.monthlyLimitCents,
      })
      .from(budgets)
      .where(gt(budgets.version, sinceVersion))
      .orderBy(asc(budgets.version)),
    tx
      .select({
        id: recurringRules.id,
        version: recurringRules.version,
        deleted: recurringRules.deleted,
        amountCents: recurringRules.amountCents,
        kind: recurringRules.kind,
        categoryId: recurringRules.categoryId,
        note: recurringRules.note,
        paidBy: recurringRules.paidBy,
        frequency: recurringRules.frequency,
        startDate: recurringRules.startDate,
        endDate: recurringRules.endDate,
        nextDueDate: recurringRules.nextDueDate,
      })
      .from(recurringRules)
      .where(gt(recurringRules.version, sinceVersion))
      .orderBy(asc(recurringRules.version)),
    tx
      .select({
        id: users.id,
        version: users.version,
        deleted: users.deleted,
        username: users.username,
        displayName: users.displayName,
        isAdmin: users.isAdmin,
      })
      .from(users)
      .where(gt(users.version, sinceVersion))
      .orderBy(asc(users.version)),
  ])
  return {
    currentVersion: await maxVersion(tx),
    changes: { categories: cats, transactions: txns, budgets: buds, recurringRules: rules, users: us },
  }
}

/**
 * Applies a push and returns everything newer than `req.lastVersion` (spec §4), in one DB
 * transaction serialized by LOCK_SYNC. `today` (YYYY-MM-DD in the configured TZ) is used to
 * recompute `nextDueDate` of rules whose startDate/frequency changed.
 *
 * Order: categories → recurringRules → transactions → budgets, so references inside one push
 * resolve. Category *deletions* are applied last, so a push that deletes a category together
 * with its last transactions/rules succeeds.
 */
export async function applySync(
  db: Db,
  _userId: string,
  req: SyncRequest,
  today: string,
): Promise<{ response: SyncResponse; rulesChanged: boolean }> {
  return db.transaction(async (tx) => {
    await lock(tx, LOCK_SYNC)
    // Measured before writing: after a backup restore the client may be ahead of the server.
    const fullResync = req.lastVersion > (await maxVersion(tx))
    const c = new Collector()
    let rulesChanged = false

    const categoryDeletes: CategoryRecord[] = []
    for (const raw of req.changes.categories ?? []) {
      const r = c.parse('categories', raw, categoryRecord)
      if (!r) continue
      if (r.deleted) categoryDeletes.push(r)
      else await c.write(tx, 'categories', r.id, (sp) => upsertCategory(sp, r))
    }
    for (const raw of req.changes.recurringRules ?? []) {
      const r = c.parse('recurringRules', raw, recurringRuleRecord)
      if (r && (await c.write(tx, 'recurringRules', r.id, (sp) => upsertRecurringRule(sp, r, today)))) {
        rulesChanged = true
      }
    }
    for (const raw of req.changes.transactions ?? []) {
      const r = c.parse('transactions', raw, transactionRecord)
      if (r) await c.write(tx, 'transactions', r.id, (sp) => upsertTransaction(sp, r))
    }
    for (const raw of req.changes.budgets ?? []) {
      const r = c.parse('budgets', raw, budgetRecord)
      if (r) await c.write(tx, 'budgets', r.id, (sp) => upsertBudget(sp, r))
    }
    for (const r of categoryDeletes) {
      await c.write(tx, 'categories', r.id, (sp) => upsertCategory(sp, r))
    }

    const pulled = await pull(tx, fullResync ? 0 : req.lastVersion)
    return { response: { ...pulled, fullResync, rejected: c.rejected }, rulesChanged }
  })
}

/** Re-reads changes after `sinceVersion` under LOCK_SYNC (used after the rules hook ran). */
export async function pullLocked(db: Db, sinceVersion: number) {
  return db.transaction(async (tx) => {
    await lock(tx, LOCK_SYNC)
    return pull(tx, sinceVersion)
  })
}
