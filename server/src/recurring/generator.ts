import { randomUUID } from 'node:crypto'
import { eq, sql } from 'drizzle-orm'
import type { Db } from '../db/client.js'
import { LOCK_SYNC, lock } from '../db/locks.js'
import { recurringRules, transactions } from '../db/schema.js'
import { dueDates } from './dates.js'

/**
 * Creates the transactions of all non-deleted rules that are due up to `today` and advances each
 * rule's nextDueDate. Idempotent: the unique index (recurring_rule_id, date) — which also covers
 * soft-deleted rows — prevents duplicates and recreation of deleted bookings.
 * Runs in one transaction under LOCK_SYNC. Returns the number of new transactions.
 */
export async function generateDueTransactions(db: Db, today: string): Promise<number> {
  return db.transaction(async (tx) => {
    await lock(tx, LOCK_SYNC)
    const rules = await tx.select().from(recurringRules).where(eq(recurringRules.deleted, false))
    let created = 0
    for (const rule of rules) {
      const { dates, nextDueDate } = dueDates(rule, today)
      if (dates.length > 0) {
        const inserted = await tx
          .insert(transactions)
          .values(
            dates.map((date) => ({
              id: randomUUID(),
              recurringRuleId: rule.id,
              date,
              amountCents: rule.amountCents,
              kind: rule.kind,
              categoryId: rule.categoryId,
              note: rule.note,
              paidBy: rule.paidBy,
            })),
          )
          .onConflictDoNothing()
          .returning({ id: transactions.id })
        created += inserted.length
      }
      if (nextDueDate !== rule.nextDueDate) {
        await tx
          .update(recurringRules)
          .set({
            nextDueDate,
            version: sql`nextval('sync_version_seq')`,
            updatedAt: sql`now()`,
          })
          .where(eq(recurringRules.id, rule.id))
      }
    }
    return created
  })
}
