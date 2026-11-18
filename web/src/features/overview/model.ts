import { type BudgetProgress, budgetProgress, expensesByCategory, expensesByPerson, type MonthSummary, summary } from '../../domain/analytics'
import { type Month, monthOf } from '../../domain/dates'
import type { Budget, Category, Member, Transaction } from '../../domain/types'

export const MAX_SLICES = 6
export const OTHERS_COLOR = '#9E9E9E'

export type Slice = { id: string; name: string; color: string; icon: string; cents: number }
export type PersonBar = { id: string; name: string; cents: number }

export type OverviewModel = {
  summary: MonthSummary
  slices: Slice[]
  people: PersonBar[]
  /** All active budgets, fullest first. */
  budgets: BudgetProgress[]
  /** Budgets at ≥ 80 %, fullest first. */
  warnings: BudgetProgress[]
  recent: Transaction[]
  hasTransactions: boolean
}

/** Same rules as the iOS overview (OverviewModel.swift). */
export function overviewModel(input: {
  txs: Transaction[]
  categories: Category[]
  members: Array<Pick<Member, 'id' | 'displayName'>>
  budgets: Budget[]
  month: Month
}): OverviewModel {
  const { txs, month } = input
  const catById = new Map(input.categories.map((c) => [c.id, c]))
  const names = new Map(input.members.map((m) => [m.id, m.displayName]))

  const totals = expensesByCategory(txs, month)
  const slices: Slice[] = totals.slice(0, MAX_SLICES).map((t) => {
    const c = catById.get(t.id)
    return { id: t.id, name: c?.name ?? 'Unbekannt', color: c?.color ?? OTHERS_COLOR, icon: c?.icon ?? '', cents: t.cents }
  })
  const rest = totals.slice(MAX_SLICES).reduce((sum, t) => sum + t.cents, 0)
  if (rest > 0) slices.push({ id: 'others', name: 'Weitere', color: OTHERS_COLOR, icon: 'ellipsis.circle', cents: rest })

  const people = expensesByPerson(txs, month).map((p) => ({ id: p.id, name: names.get(p.id) ?? 'Unbekannt', cents: p.cents }))

  // Archived or deleted categories (missing here) do not warn.
  const live = input.budgets.filter((b) => catById.get(b.categoryId)?.archived === false)
  const budgets = budgetProgress(live, txs, month).sort((a, b) => b.ratio - a.ratio)
  const warnings = budgets.filter((p) => p.level !== 'ok')

  const monthTxs = txs.filter((t) => monthOf(t.date) === month)
  const recent = [...monthTxs].sort((a, b) => (a.date === b.date ? b.version - a.version : a.date < b.date ? 1 : -1)).slice(0, 5)

  return { summary: summary(txs, month), slices, people, budgets, warnings, recent, hasTransactions: monthTxs.length > 0 }
}
