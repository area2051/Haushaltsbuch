import type { Category } from './types'

export type CategoryTree = {
  byId: Map<string, Category>
  /** The main category of `id` (itself for main categories and unknown ids). */
  rootOf(id: string): string
  /** Direct children, by sortOrder then name. */
  childrenOf(id: string): Category[]
  /** Display colour: always the main category's (undefined for an unknown id). */
  colorFor(id: string): string | undefined
  /** „Haupt · Kind“, the plain name for a main category, „Unbekannt“ for an unknown id. */
  labelFor(id: string): string
  /** Not archived, and the parent (if any) not archived either. */
  isSelectable(c: Category): boolean
}

export function categoryTree(cats: Category[]): CategoryTree {
  const byId = new Map(cats.map((c) => [c.id, c]))
  const parentOf = (c: Category | undefined): Category | undefined => (c?.parentId ? byId.get(c.parentId) : undefined)
  const children = new Map<string, Category[]>()
  for (const c of cats) {
    if (!c.parentId) continue
    const list = children.get(c.parentId)
    if (list) list.push(c)
    else children.set(c.parentId, [c])
  }
  for (const list of children.values()) list.sort((a, b) => a.sortOrder - b.sortOrder || a.name.localeCompare(b.name))
  return {
    byId,
    rootOf: (id) => parentOf(byId.get(id))?.id ?? id,
    colorFor: (id) => byId.get(parentOf(byId.get(id))?.id ?? id)?.color,
    childrenOf: (id) => children.get(id) ?? [],
    labelFor(id) {
      const c = byId.get(id)
      if (!c) return 'Unbekannt'
      const p = parentOf(c)
      return p ? `${p.name} · ${c.name}` : c.name
    },
    isSelectable: (c) => !c.archived && !parentOf(c)?.archived,
  }
}
