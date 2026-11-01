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

/** UUID, normalised to lowercase (Swift encodes uppercase, Postgres returns lowercase). */
const id = z.uuid().overwrite((s) => s.toLowerCase())
/** Text that Postgres can store: NUL (U+0000) would raise SQLSTATE 22021. */
const text = () => z.string().refine((s) => !s.includes('\u0000'), 'must not contain NUL characters')
const amountCents = z.number().int().min(1).max(INT32_MAX)
const kind = z.enum(['income', 'expense'])
const note = text().max(200).nullable()

const base = { id, deleted: z.boolean() }

// ---- Records as pushed by the client (request shape: no `version`, no `nextDueDate`) ----

export const categoryRecord = z.object({
  ...base,
  name: text().min(1).max(40),
  icon: text().max(100),
  color: z.string().regex(/^#[0-9A-Fa-f]{6}$/),
  kind,
  sortOrder: z.number().int().min(-INT32_MAX).max(INT32_MAX),
  archived: z.boolean(),
}).meta({ id: 'CategoryRecord' })

export const transactionRecord = z.object({
  ...base,
  amountCents,
  kind,
  categoryId: id,
  date: calendarDate,
  note,
  paidBy: id,
  recurringRuleId: id.nullable(),
}).meta({ id: 'TransactionRecord' })

export const budgetRecord = z.object({
  ...base,
  categoryId: id,
  monthlyLimitCents: z.number().int().min(1).max(INT32_MAX),
}).meta({ id: 'BudgetRecord' })

export const recurringRuleRecord = z.object({
  ...base,
  amountCents,
  kind,
  categoryId: id,
  note,
  paidBy: id,
  frequency: z.enum(['weekly', 'monthly', 'yearly']),
  startDate: calendarDate.refine((s) => s >= '2000-01-01', 'must be on or after 2000-01-01'),
  endDate: calendarDate.nullable(),
}).refine((r) => r.endDate === null || r.endDate >= r.startDate, {
  message: 'must be on or after startDate',
  path: ['endDate'],
}).meta({ id: 'RecurringRuleRecord' })

export type CategoryRecord = z.infer<typeof categoryRecord>
export type TransactionRecord = z.infer<typeof transactionRecord>
export type BudgetRecord = z.infer<typeof budgetRecord>
export type RecurringRuleRecord = z.infer<typeof recurringRuleRecord>

// ---- Records as returned by the server ----
//
// Plain shapes (types/formats only) without the input refinements above (lengths, startDate >= 2000,
// endDate >= startDate, NUL check, ...): the zod serializer validates responses, so a single stored row
// outside the input contract (older data, manual fix in the DB) must not turn every sync into a 500.

const version = z.number().int()
const outDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/)
/** Lenient UUID format (any 8-4-4-4-12 hex), not the strict RFC check used for input. */
const outId = z.guid()
const outBase = { id: outId, version, deleted: z.boolean() }

export const categoryRecordOut = z.object({
  ...outBase,
  name: z.string(),
  icon: z.string(),
  color: z.string(),
  kind,
  sortOrder: z.number().int(),
  archived: z.boolean(),
}).meta({ id: 'CategoryRecordOut' })

export const transactionRecordOut = z.object({
  ...outBase,
  amountCents: z.number().int(),
  kind,
  categoryId: outId,
  date: outDate,
  note: z.string().nullable(),
  paidBy: outId,
  recurringRuleId: outId.nullable(),
}).meta({ id: 'TransactionRecordOut' })

export const budgetRecordOut = z.object({
  ...outBase,
  categoryId: outId,
  monthlyLimitCents: z.number().int(),
}).meta({ id: 'BudgetRecordOut' })

export const recurringRuleRecordOut = z.object({
  ...outBase,
  amountCents: z.number().int(),
  kind,
  categoryId: outId,
  note: z.string().nullable(),
  paidBy: outId,
  frequency: z.enum(['weekly', 'monthly', 'yearly']),
  startDate: outDate,
  endDate: outDate.nullable(),
  nextDueDate: outDate,
}).meta({ id: 'RecurringRuleRecordOut' })
/**
 * UserDto plus sync fields. `deleted` is included because the spec requires deleted users
 * to be synced as well (otherwise a client could not tell that a member was removed).
 */
export const userRecord = userDto.extend({ version, deleted: z.boolean() }).meta({ id: 'UserRecord' })

export type UserRecord = z.infer<typeof userRecord>

// ---- Request ----

/**
 * Typed request schema. It is the documented body schema of `POST /sync` (OpenAPI / iOS client),
 * but the route does NOT validate records with it: see `syncRequestEnvelope`.
 */
export const syncRequest = z.object({
  lastVersion: z.number().int().min(0).max(Number.MAX_SAFE_INTEGER),
  changes: z.object({
    categories: z.array(categoryRecord).optional(),
    transactions: z.array(transactionRecord).optional(),
    budgets: z.array(budgetRecord).optional(),
    recurringRules: z.array(recurringRuleRecord).optional(),
  }),
}).meta({ id: 'SyncRequest' })

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
}).meta({ id: 'RejectedRecord' })

export const syncChanges = z.object({
  categories: z.array(categoryRecordOut),
  transactions: z.array(transactionRecordOut),
  budgets: z.array(budgetRecordOut),
  recurringRules: z.array(recurringRuleRecordOut),
  users: z.array(userRecord),
}).meta({ id: 'SyncChanges' })

export const syncResponse = z.object({
  currentVersion: z.number().int(),
  fullResync: z.boolean(),
  changes: syncChanges,
  rejected: z.array(rejectedRecord),
}).meta({ id: 'SyncResponse' })

export type SyncChanges = z.infer<typeof syncChanges>
export type SyncResponse = z.infer<typeof syncResponse>
