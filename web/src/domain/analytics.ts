import type { CategoryTree } from './categoryTree'
import { addDays, addMonths, type Day, type Month, monthOf } from './dates'
import type { Budget, Category, Kind, Transaction } from './types'

export type MonthSummary = { incomeCents: number; expenseCents: number; balanceCents: number }
export type Total = { id: string; cents: number }
export type BudgetLevel = 'ok' | 'warning' | 'exceeded'
export type BudgetProgress = {
  categoryId: string
  spentCents: number
  limitCents: number
  ratio: number
  level: BudgetLevel
}

function totals(txs: Transaction[], m: Month): MonthSummary {
  let income = 0
  let expense = 0
  for (const t of txs) {
    if (monthOf(t.date) !== m) continue
    if (t.kind === 'income') income += t.amountCents
    else expense += t.amountCents
  }
  return { incomeCents: income, expenseCents: expense, balanceCents: income - expense }
}

export const summary = (txs: Transaction[], m: Month): MonthSummary => totals(txs, m)

/** Month expenses summed by `key`. */
function expensesBy(txs: Transaction[], m: Month, key: (t: Transaction) => string): Map<string, number> {
  const sums = new Map<string, number>()
  for (const t of txs) {
    if (t.kind !== 'expense' || monthOf(t.date) !== m) continue
    const k = key(t)
    sums.set(k, (sums.get(k) ?? 0) + t.amountCents)
  }
  return sums
}

/** Descending by amount; ties by id for a stable order. */
const sorted = (sums: Map<string, number>): Total[] =>
  [...sums].map(([id, cents]) => ({ id, cents })).sort((a, b) => b.cents - a.cents || a.id.localeCompare(b.id))

const identity = (id: string): string => id

/** Month expenses per main category when `rootOf` is given (subcategories roll up into their parent). */
export const expensesByCategory = (txs: Transaction[], m: Month, rootOf: (id: string) => string = identity): Total[] =>
  sorted(expensesBy(txs, m, (t) => rootOf(t.categoryId)))

/** Month expenses of one main category: bookings on it directly (`id = parentId`) and per child. */
export function subcategoryBreakdown(txs: Transaction[], m: Month, parentId: string, tree: CategoryTree): Total[] {
  return sorted(expensesBy(txs.filter((t) => tree.rootOf(t.categoryId) === parentId), m, (t) => t.categoryId))
}

export const expensesByPerson = (txs: Transaction[], m: Month): Total[] => sorted(expensesBy(txs, m, (t) => t.paidBy))

/** ok < 80 %, warning ≥ 80 %, exceeded ≥ 100 % (integer comparisons, as on iOS). */
export function budgetLevel(spent: number, limit: number): BudgetLevel {
  if (limit <= 0) return spent > 0 ? 'exceeded' : 'ok'
  if (spent >= limit) return 'exceeded'
  if (spent * 5 >= limit * 4) return 'warning'
  return 'ok'
}

export function budgetProgress(budgets: Budget[], txs: Transaction[], m: Month, rootOf: (id: string) => string = identity): BudgetProgress[] {
  const spent = expensesBy(txs, m, (t) => rootOf(t.categoryId))
  return budgets.map((b) => {
    const s = spent.get(b.categoryId) ?? 0
    const limit = b.monthlyLimitCents
    return {
      categoryId: b.categoryId,
      spentCents: s,
      limitCents: limit,
      ratio: limit > 0 ? s / limit : s > 0 ? Infinity : 0,
      level: budgetLevel(s, limit),
    }
  })
}

/** Active categories of `kind`, most used in the last 90 days (today − 89 … today) first, then sortOrder. */
export function rankCategories(cats: Category[], txs: Transaction[], kind: Kind, now: Day): Category[] {
  const start = addDays(now, -89)
  const counts = new Map<string, number>()
  for (const t of txs) {
    if (t.kind === kind && t.date >= start && t.date <= now) counts.set(t.categoryId, (counts.get(t.categoryId) ?? 0) + 1)
  }
  return cats
    .filter((c) => c.kind === kind && !c.archived)
    .sort((a, b) => (counts.get(b.id) ?? 0) - (counts.get(a.id) ?? 0) || a.sortOrder - b.sortOrder)
}

/** Income/expenses for the `count` months ending with `end`, oldest first. */
export function monthlyTrend(txs: Transaction[], end: Month, count: number): Array<{ month: Month } & MonthSummary> {
  return Array.from({ length: count }, (_, i) => {
    const month = addMonths(end, i - count + 1)
    return { month, ...totals(txs, month) }
  })
}

/** Running total of expenses per day of the month; index 0 is day 1. */
export function cumulativeDailyExpenses(txs: Transaction[], m: Month, days: number): number[] {
  const perDay = new Array<number>(days).fill(0)
  for (const t of txs) {
    if (t.kind !== 'expense' || monthOf(t.date) !== m) continue
    const d = Number(t.date.slice(8, 10))
    if (d <= days) perDay[d - 1]! += t.amountCents
  }
  let acc = 0
  return perDay.map((v) => (acc += v))
}

export type CategoryTrend = { top: string[]; rows: Array<{ month: Month; others: number } & Record<string, number | string>> }

/**
 * Expenses per month for the `topN` categories with the most spending over the window
 * (`count` months ending with `end`, oldest first); everything else is summed as `others`.
 */
export function categoryTrend(txs: Transaction[], end: Month, count: number, topN: number, rootOf: (id: string) => string = identity): CategoryTrend {
  const months = Array.from({ length: count }, (_, i) => addMonths(end, i - count + 1))
  const perMonth = new Map(months.map((m) => [m, new Map<string, number>()]))
  const totals = new Map<string, number>()
  for (const t of txs) {
    const m = perMonth.get(monthOf(t.date))
    if (t.kind !== 'expense' || !m) continue
    const id = rootOf(t.categoryId)
    m.set(id, (m.get(id) ?? 0) + t.amountCents)
    totals.set(id, (totals.get(id) ?? 0) + t.amountCents)
  }
  const top = sorted(totals).slice(0, topN).map((t) => t.id)
  const rows = months.map((month) => {
    const sums = perMonth.get(month)!
    const row: { month: Month; others: number } & Record<string, number | string> = { month, others: 0 }
    for (const id of top) row[id] = sums.get(id) ?? 0
    for (const [id, cents] of sums) if (!top.includes(id)) row.others += cents
    return row
  })
  return { top, rows }
}
