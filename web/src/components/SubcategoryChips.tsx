import type { CategoryTree } from '../domain/categoryTree'
import { cn } from '../lib/cn'

/**
 * Chip row below a main category: „Allgemein“ (= the main category itself) and its selectable
 * subcategories. Renders nothing when the main category has none.
 */
export function SubcategoryChips({ parentId, value, onChange, tree }: { parentId: string; value: string; onChange(id: string): void; tree: CategoryTree }) {
  const children = tree.childrenOf(parentId).filter(tree.isSelectable)
  if (children.length === 0) return null
  const options = [{ id: parentId, name: 'Allgemein' }, ...children]
  return (
    <div role="group" aria-label="Unterkategorie" className="flex flex-wrap gap-2">
      {options.map((o) => {
        const selected = o.id === value
        return (
          <button
            key={o.id}
            type="button"
            aria-pressed={selected}
            onClick={() => onChange(o.id)}
            className={cn(
              'inline-flex h-9 items-center rounded-full px-3.5 text-[14px] font-medium transition active:scale-95 disabled:opacity-40',
              selected ? 'bg-ink text-on-ink' : 'bg-tile text-ink-2 shadow-tile hover:bg-tile-2',
            )}
          >
            {o.name}
          </button>
        )
      })}
    </div>
  )
}
