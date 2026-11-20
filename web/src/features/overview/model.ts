import { type BudgetProgress, budgetProgress, subcategoryBreakdown, expensesByCategory, expensesByPerson, type MonthSummary, summary } from '../../domain/analytics'
import { categoryTree } from '../../domain/categoryTree'
import { type Month, monthOf } from '../../domain/dates'
import type { Budget, Category, Member, Transaction } from '../../domain/types'

export const MAX_SLICES = 6
export const OTHERS_COLOR = '#9E9E9E'

export type Slice = { id: string; name: string; color: string; icon: string; cents: number; children: Slice[] }
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

  const tree = categoryTree(input.categories)
  const { rootOf } = tree
  const totals = expensesByCategory(txs, month, rootOf)
  const slices: Slice[] = totals.slice(0, MAX_SLICES).map((t) => {
    const c = catById.get(t.id)
    const color = c?.color ?? OTHERS_COLOR
    const parts = subcategoryBreakdown(txs, month, t.id, tree).filter((s) => s.cents > 0)
    // Without any subcategory spending there is nothing to expand.
    const children = parts.every((s) => s.id === t.id) ? [] : parts.map((s) => {
        const sub = catById.get(s.id)
        const own = s.id === t.id
        return { id: s.id, name: own ? 'Allgemein' : (sub?.name ?? 'Unbekannt'), color, icon: own ? (c?.icon ?? '') : (sub?.icon ?? ''), cents: s.cents, children: [] }
      })
    return { id: t.id, name: c?.name ?? 'Unbekannt', color, icon: c?.icon ?? '', cents: t.cents, children }
  })
  const rest = totals.slice(MAX_SLICES).reduce((sum, t) => sum + t.cents, 0)
  if (rest > 0) slices.push({ id: 'others', name: 'Weitere', color: OTHERS_COLOR, icon: 'ellipsis.circle', cents: rest, children: [] })

  const people = expensesByPerson(txs, month).map((p) => ({ id: p.id, name: names.get(p.id) ?? 'Unbekannt', cents: p.cents }))

  // Archived or deleted categories (missing here) do not warn.
  const live = input.budgets.filter((b) => catById.get(b.categoryId)?.archived === false)
  const budgets = budgetProgress(live, txs, month, rootOf).sort((a, b) => b.ratio - a.ratio)
  const warnings = budgets.filter((p) => p.level !== 'ok')

  const monthTxs = txs.filter((t) => monthOf(t.date) === month)
  const recent = [...monthTxs].sort((a, b) => (a.date === b.date ? b.version - a.version : a.date < b.date ? 1 : -1)).slice(0, 5)

  return { summary: summary(txs, month), slices, people, budgets, warnings, recent, hasTransactions: monthTxs.length > 0 }
}
