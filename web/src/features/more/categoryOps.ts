import type { Budget, Category, CategoryInput, Kind, RecurringRule, Transaction } from '../../domain/types'

const NAME_MAX = 40

export function categoryNameProblem(name: string): 'empty' | 'tooLong' | null {
  const n = name.trim()
  if (!n) return 'empty'
  if (n.length > NAME_MAX) return 'tooLong'
  return null
}

const input = ({ version: _v, ...rest }: Category): CategoryInput => rest

export type CategoryDraft = { name: string; icon: string; color: string; kind: Kind; parentId: string | null }

const nextSortOrder = (siblings: Category[]) => (siblings.length ? Math.max(...siblings.map((c) => c.sortOrder)) + 1 : 0)

/** New category at the end of its siblings; a subcategory takes the parent's kind and color. */
export function newCategory(d: CategoryDraft, existing: Category[], id: string): CategoryInput {
  const parent = d.parentId ? existing.find((c) => c.id === d.parentId) : undefined
  const kind = parent?.kind ?? d.kind
  const siblings = existing.filter((c) => (d.parentId ? c.parentId === d.parentId : !c.parentId && c.kind === kind))
  return {
    id, name: d.name.trim(), icon: d.icon, color: parent?.color ?? d.color, kind,
    sortOrder: nextSortOrder(siblings), parentId: d.parentId, archived: false, deleted: false,
  }
}

/** Re-parent `c` (null = make it a main category): new parent's color, last among the new siblings. */
export function moveCategory(c: Category, parentId: string | null, all: Category[]): CategoryInput {
  const parent = parentId ? all.find((p) => p.id === parentId) : undefined
  const siblings = all.filter((o) => o.id !== c.id && (parentId ? o.parentId === parentId : !o.parentId && o.kind === c.kind))
  return { ...input(c), parentId, color: parent?.color ?? c.color, sortOrder: nextSortOrder(siblings) }
}

/** What happens to c's budget when it becomes a subcategory of `parentId` (shown before saving). */
export function moveBudgetEffect(c: Category, parentId: string, budgets: Budget[]): 'none' | 'moves' | 'deleted' {
  const active = (id: string) => budgets.some((b) => b.categoryId === id && !b.deleted)
  if (c.parentId === parentId || !active(c.id)) return 'none'
  return active(parentId) ? 'deleted' : 'moves'
}

/** Possible parents: active main categories of the same kind, not c itself; none if c has children. */
export function parentOptions(c: Category | null, all: Category[], kind: Kind): Category[] {
  if (c && all.some((o) => o.parentId === c.id && !o.deleted)) return []
  return all.filter((o) => !o.parentId && o.kind === kind && !o.archived && !o.deleted && o.id !== c?.id)
}

export type Removal =
  | { action: 'blocked' }
  | { action: 'archive' | 'delete'; records: Array<{ table: 'categories'; record: CategoryInput }> }

/**
 * A category with active subcategories is blocked. Like iOS: a category still used by transactions or
 * rules is archived (the server would reject the delete with `category_in_use`); otherwise it is
 * deleted. The server deletes the category's budget in the same transaction, so a rejected delete
 * never loses the budget.
 */
export function removalPlan(c: Category, txs: Transaction[], rules: RecurringRule[], all: Category[]): Removal {
  if (all.some((o) => o.parentId === c.id && !o.deleted)) return { action: 'blocked' }
  const used = txs.some((t) => t.categoryId === c.id) || rules.some((r) => r.categoryId === c.id)
  return used
    ? { action: 'archive', records: [{ table: 'categories', record: { ...input(c), archived: true } }] }
    : { action: 'delete', records: [{ table: 'categories', record: { ...input(c), deleted: true } }] }
}

/** sortOrder 0…n-1 in the given order; only categories whose order changed. */
export function reorder(ordered: Category[]): CategoryInput[] {
  return ordered.flatMap((c, i) => (c.sortOrder === i ? [] : [{ ...input(c), sortOrder: i }]))
}
