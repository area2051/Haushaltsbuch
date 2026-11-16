import type { Category, CategoryInput, Kind, RecurringRule, Transaction } from '../../domain/types'

const NAME_MAX = 40

export function categoryNameProblem(name: string): 'empty' | 'tooLong' | null {
  const n = name.trim()
  if (!n) return 'empty'
  if (n.length > NAME_MAX) return 'tooLong'
  return null
}

const input = ({ version: _v, ...rest }: Category): CategoryInput => rest

export type CategoryDraft = { name: string; icon: string; color: string; kind: Kind }

/** New category at the end of its kind. */
export function newCategory(d: CategoryDraft, existing: Category[], id: string): CategoryInput {
  const sameKind = existing.filter((c) => c.kind === d.kind).map((c) => c.sortOrder)
  return { id, name: d.name.trim(), icon: d.icon, color: d.color, kind: d.kind, sortOrder: sameKind.length ? Math.max(...sameKind) + 1 : 0, archived: false, deleted: false }
}

export type Removal = { action: 'archive' | 'delete'; records: Array<{ table: 'categories'; record: CategoryInput }> }

/**
 * Like iOS: a category still used by transactions or rules is archived (the server would reject
 * the delete with `category_in_use`); otherwise it is deleted. The server deletes the category's
 * budget in the same transaction, so a rejected delete never loses the budget.
 */
export function removalPlan(c: Category, txs: Transaction[], rules: RecurringRule[]): Removal {
  const used = txs.some((t) => t.categoryId === c.id) || rules.some((r) => r.categoryId === c.id)
  return used
    ? { action: 'archive', records: [{ table: 'categories', record: { ...input(c), archived: true } }] }
    : { action: 'delete', records: [{ table: 'categories', record: { ...input(c), deleted: true } }] }
}

/** sortOrder 0…n-1 in the given order; only categories whose order changed. */
export function reorder(ordered: Category[]): CategoryInput[] {
  return ordered.flatMap((c, i) => (c.sortOrder === i ? [] : [{ ...input(c), sortOrder: i }]))
}
