import { sql } from 'drizzle-orm'
import {
  bigint,
  boolean,
  check,
  date,
  index,
  integer,
  pgEnum,
  pgSequence,
  pgTable,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from 'drizzle-orm/pg-core'

export const syncVersionSeq = pgSequence('sync_version_seq')

export const kindEnum = pgEnum('kind', ['income', 'expense'])
export const frequencyEnum = pgEnum('frequency', ['weekly', 'monthly', 'yearly'])

const syncColumns = {
  id: uuid('id').primaryKey().defaultRandom(),
  version: bigint('version', { mode: 'number' })
    .notNull()
    .default(sql`nextval('sync_version_seq')`),
  deleted: boolean('deleted').notNull().default(false),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
}

export const users = pgTable(
  'users',
  {
    ...syncColumns,
    username: text('username').notNull().unique(),
    displayName: text('display_name').notNull(),
    passwordHash: text('password_hash').notNull(),
    isAdmin: boolean('is_admin').notNull().default(false),
  },
  (t) => [index('users_version_idx').on(t.version)],
)

export const refreshTokens = pgTable(
  'refresh_tokens',
  {
  id: uuid('id').primaryKey().defaultRandom(),
  userId: uuid('user_id')
    .notNull()
    .references(() => users.id),
  tokenHash: text('token_hash').notNull(),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
  deviceName: text('device_name'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index('refresh_tokens_token_hash_idx').on(t.tokenHash)],
)

export const categories = pgTable(
  'categories',
  {
    ...syncColumns,
    name: text('name').notNull(),
    icon: text('icon').notNull(),
    color: text('color').notNull(),
    kind: kindEnum('kind').notNull(),
    sortOrder: integer('sort_order').notNull().default(0),
    archived: boolean('archived').notNull().default(false),
  },
  (t) => [index('categories_version_idx').on(t.version)],
)

export const recurringRules = pgTable(
  'recurring_rules',
  {
    ...syncColumns,
    amountCents: integer('amount_cents').notNull(),
    kind: kindEnum('kind').notNull(),
    categoryId: uuid('category_id')
      .notNull()
      .references(() => categories.id),
    note: text('note'),
    paidBy: uuid('paid_by')
      .notNull()
      .references(() => users.id),
    frequency: frequencyEnum('frequency').notNull(),
    startDate: date('start_date', { mode: 'string' }).notNull(),
    endDate: date('end_date', { mode: 'string' }),
    nextDueDate: date('next_due_date', { mode: 'string' }).notNull(),
  },
  (t) => [
    index('recurring_rules_version_idx').on(t.version),
    check('recurring_rules_amount_positive', sql`${t.amountCents} > 0`),
  ],
)

export const transactions = pgTable(
  'transactions',
  {
    ...syncColumns,
    amountCents: integer('amount_cents').notNull(),
    kind: kindEnum('kind').notNull(),
    categoryId: uuid('category_id')
      .notNull()
      .references(() => categories.id),
    date: date('date', { mode: 'string' }).notNull(),
    note: text('note'),
    paidBy: uuid('paid_by')
      .notNull()
      .references(() => users.id),
    recurringRuleId: uuid('recurring_rule_id').references(() => recurringRules.id),
  },
  (t) => [
    index('transactions_version_idx').on(t.version),
    uniqueIndex('transactions_rule_date_uq')
      .on(t.recurringRuleId, t.date)
      .where(sql`${t.recurringRuleId} IS NOT NULL`),
    check('transactions_amount_positive', sql`${t.amountCents} > 0`),
  ],
)

export const budgets = pgTable(
  'budgets',
  {
    ...syncColumns,
    categoryId: uuid('category_id')
      .notNull()
      .references(() => categories.id),
    monthlyLimitCents: integer('monthly_limit_cents').notNull(),
  },
  (t) => [
    index('budgets_version_idx').on(t.version),
    uniqueIndex('budgets_category_active_uq')
      .on(t.categoryId)
      .where(sql`NOT ${t.deleted}`),
  ],
)
