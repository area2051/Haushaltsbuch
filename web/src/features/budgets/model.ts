import { type BudgetProgress, budgetProgress, expensesByCategory } from '../../domain/analytics'
import { categoryTree } from '../../domain/categoryTree'
import type { Month } from '../../domain/dates'
import type { Budget, BudgetInput, Category, Transaction } from '../../domain/types'

export type BudgetRow = { category: Category; budget?: Budget; spentCents: number; progress?: BudgetProgress }

/** Active main expense categories (sort order; spending includes subcategories) with month spending and their budget, if any. */
export function budgetRows(categories: Category[], budgets: Budget[], txs: Transaction[], month: Month) {
  const { rootOf } = categoryTree(categories)
  const spent = new Map(expensesByCategory(txs, month, rootOf).map((t) => [t.id, t.cents]))
  const byCategory = new Map(budgets.map((b) => [b.categoryId, b]))
  const progress = new Map(budgetProgress(budgets, txs, month, rootOf).map((p) => [p.categoryId, p]))
  const items: BudgetRow[] = categories
    .filter((c) => c.kind === 'expense' && !c.archived && !c.parentId)
    .sort((a, b) => a.sortOrder - b.sortOrder || a.name.localeCompare(b.name))
    .map((category) => ({
      category,
      budget: byCategory.get(category.id),
      spentCents: spent.get(category.id) ?? 0,
      progress: progress.get(category.id),
    }))
  const budgeted = items.filter((r) => r.budget)
  return {
    items,
    total: {
      limitCents: budgeted.reduce((s, r) => s + r.budget!.monthlyLimitCents, 0),
      spentCents: budgeted.reduce((s, r) => s + r.spentCents, 0),
    },
  }
}

/** Upsert for the category's budget: reuses the existing record (one budget per category). */
export function budgetRecord(existing: Budget | undefined, categoryId: string, limitCents: number, newId: string): BudgetInput {
  return { id: existing?.id ?? newId, categoryId, monthlyLimitCents: limitCents, deleted: false }
}

export function removedBudget(b: Budget): BudgetInput {
  return { id: b.id, categoryId: b.categoryId, monthlyLimitCents: b.monthlyLimitCents, deleted: true }
}
