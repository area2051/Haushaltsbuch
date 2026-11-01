import { z } from 'zod'
import { userDto } from '../users/dto.js'

const INT32_MAX = 2147483647

/** Calendar date YYYY-MM-DD that actually exists (and is storable in Postgres: year >= 1). */
export const calendarDate = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, 'must be a date YYYY-MM-DD')
  .refine((s) => {
    const [y, m, d] = s.split('-').map(Number) as [number, number, number]
    const dt = new Date(Date.UTC(y, m - 1, d))
    return y >= 1 && dt.getUTCFullYear() === y && dt.getUTCMonth() === m - 1 && dt.getUTCDate() === d
  }, 'must be a valid calendar date')

const id = z.uuid()
const amountCents = z.number().int().min(1).max(INT32_MAX)
const kind = z.enum(['income', 'expense'])
const note = z.string().max(200).nullable()

const base = { id, deleted: z.boolean() }

// ---- Records as pushed by the client (request shape: no `version`, no `nextDueDate`) ----

export const categoryRecord = z.object({
  ...base,
  name: z.string().min(1).max(40),
  icon: z.string().max(100),
  color: z.string().regex(/^#[0-9A-Fa-f]{6}$/),
  kind,
  sortOrder: z.number().int().min(-INT32_MAX).max(INT32_MAX),
  archived: z.boolean(),
})

export const transactionRecord = z.object({
  ...base,
  amountCents,
  kind,
  categoryId: id,
  date: calendarDate,
  note,
  paidBy: id,
  recurringRuleId: id.nullable(),
})

export const budgetRecord = z.object({
  ...base,
  categoryId: id,
  monthlyLimitCents: z.number().int().min(1).max(INT32_MAX),
})

export const recurringRuleRecord = z.object({
  ...base,
  amountCents,
  kind,
  categoryId: id,
  note,
  paidBy: id,
  frequency: z.enum(['weekly', 'monthly', 'yearly']),
  startDate: calendarDate,
  endDate: calendarDate.nullable(),
})

export type CategoryRecord = z.infer<typeof categoryRecord>
export type TransactionRecord = z.infer<typeof transactionRecord>
export type BudgetRecord = z.infer<typeof budgetRecord>
export type RecurringRuleRecord = z.infer<typeof recurringRuleRecord>

// ---- Records as returned by the server ----

const version = z.number().int()

export const categoryRecordOut = categoryRecord.extend({ version })
export const transactionRecordOut = transactionRecord.extend({ version })
export const budgetRecordOut = budgetRecord.extend({ version })
export const recurringRuleRecordOut = recurringRuleRecord.extend({ version, nextDueDate: calendarDate })
/**
 * UserDto plus sync fields. `deleted` is included because the spec requires deleted users
 * to be synced as well (otherwise a client could not tell that a member was removed).
 */
export const userRecord = userDto.extend({ version, deleted: z.boolean() })

export type UserRecord = z.infer<typeof userRecord>

// ---- Request ----

/**
 * Typed request schema. It is the documented body schema of `POST /sync` (OpenAPI / iOS client),
 * but the route does NOT validate records with it: see `syncRequestEnvelope`.
 */
export const syncRequest = z.object({
  lastVersion: z.number().int().min(0),
  changes: z.object({
    categories: z.array(categoryRecord).optional(),
    transactions: z.array(transactionRecord).optional(),
    budgets: z.array(budgetRecord).optional(),
    recurringRules: z.array(recurringRuleRecord).optional(),
  }),
})

/**
 * What the route actually validates: only the envelope. Records stay `unknown` and are parsed
 * one by one in `applySync`, so one invalid record is rejected alone instead of failing the request.
 */
export const syncRequestEnvelope = z.object({
  lastVersion: z.number().int().min(0).max(Number.MAX_SAFE_INTEGER),
  changes: z.object({
    categories: z.array(z.unknown()).optional(),
    transactions: z.array(z.unknown()).optional(),
    budgets: z.array(z.unknown()).optional(),
    recurringRules: z.array(z.unknown()).optional(),
  }),
})

/** Input of `applySync`: envelope-validated, records not yet parsed. */
export type SyncRequest = z.infer<typeof syncRequestEnvelope>

// ---- Response ----

export const rejectedRecord = z.object({
  table: z.string(),
  id: z.string().nullable(),
  reason: z.string(),
})

export const syncChanges = z.object({
  categories: z.array(categoryRecordOut),
  transactions: z.array(transactionRecordOut),
  budgets: z.array(budgetRecordOut),
  recurringRules: z.array(recurringRuleRecordOut),
  users: z.array(userRecord),
})

export const syncResponse = z.object({
  currentVersion: z.number().int(),
  fullResync: z.boolean(),
  changes: syncChanges,
  rejected: z.array(rejectedRecord),
})

export type SyncChanges = z.infer<typeof syncChanges>
export type SyncResponse = z.infer<typeof syncResponse>
