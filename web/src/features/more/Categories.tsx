import { ArchiveRestore, ArrowDown, ArrowUp, Plus } from 'lucide-react'
import { type FormEvent, useMemo, useState } from 'react'
import { toast } from 'sonner'
import { useCategoryTree, useData } from '../../app/AppContext'
import { useSaver } from '../../app/useSaver'
import { CategoryIcon } from '../../components/CategoryIcon'
import { Button } from '../../components/ui/Button'
import { ConfirmButton } from '../../components/ui/ConfirmButton'
import { Field, Input, Select } from '../../components/ui/Field'
import { BackLink, PageHeader } from '../../components/ui/Misc'
import { Segmented } from '../../components/ui/Segmented'
import { Sheet } from '../../components/ui/Sheet'
import { CATEGORY_COLORS, CATEGORY_SYMBOLS, iconFor } from '../../domain/icons'
import type { Category, Kind } from '../../domain/types'
import { cn } from '../../lib/cn'
import { uuidv4 } from '../../lib/uuid'
import { categoryNameProblem, moveBudgetEffect, moveCategory, newCategory, parentOptions, removalPlan, reorder } from './categoryOps'

const byOrder = (a: Category, b: Category) => a.sortOrder - b.sortOrder || a.name.localeCompare(b.name)

export function Categories() {
  const data = useData()
  const save = useSaver()
  const [kind, setKind] = useState<Kind>('expense')
  const [editing, setEditing] = useState<Category | 'new' | null>(null)

  const tree = useCategoryTree()
  const all = useMemo(() => [...data.categories.values()].sort(byOrder), [data.categories])
  const active = all.filter((c) => !c.archived && !c.parentId && c.kind === kind)
  // Like iOS: everything not selectable, i.e. archived ones and the children of an archived parent.
  const archived = all.filter((c) => !tree.isSelectable(c) && c.kind === kind)

  /** Swaps `siblings[index]` with its neighbour (main categories, or the children of one parent). */
  async function move(siblings: Category[], index: number, dir: -1 | 1) {
    // Same as iOS: renumber the whole list (active first, then archived), save only changes.
    const list = all.filter((c) => !c.archived)
    const a = siblings[index]!
    const b = siblings[index + dir]!
    const ordered = list.map((c) => (c === a ? b : c === b ? a : c))
    for (const record of reorder([...ordered, ...all.filter((c) => c.archived)])) await save('categories', record)
  }

  const row = (c: Category, siblings: Category[], i: number, child: boolean) => (
    <li key={c.id} className={cn('flex items-center gap-2 rounded-tile bg-tile p-2 pr-3 shadow-tile', child && 'ml-8 bg-tile/70 shadow-none')}>
      <button onClick={() => setEditing(c)} className="flex min-w-0 flex-1 items-center gap-3 rounded-2xl p-1 text-left">
        <CategoryIcon icon={c.icon} color={tree.colorFor(c.id) ?? c.color} size={child ? 'sm' : 'md'} />
        <span className="truncate text-[15px] font-medium">{c.name}</span>
      </button>
      <Button variant="ghost" size="icon" aria-label={`${c.name} nach oben`} disabled={i === 0} onClick={() => void move(siblings, i, -1)}>
        <ArrowUp className="size-5" />
      </Button>
      <Button variant="ghost" size="icon" aria-label={`${c.name} nach unten`} disabled={i === siblings.length - 1} onClick={() => void move(siblings, i, 1)}>
        <ArrowDown className="size-5" />
      </Button>
    </li>
  )

  return (
    <div className="mx-auto max-w-2xl">
      <BackLink />
      <PageHeader
        title="Kategorien"
        actions={
          <Button variant="primary" size="sm" onClick={() => setEditing('new')}>
            <Plus className="size-4" /> Neu
          </Button>
        }
      />
      <Segmented<Kind>
        label="Art"
        value={kind}
        onChange={setKind}
        options={[
          { value: 'expense', label: 'Ausgaben' },
          { value: 'income', label: 'Einnahmen' },
        ]}
        className="mb-4"
      />
      <ul className="space-y-2">
        {active.flatMap((c, i) => {
          const children = tree.childrenOf(c.id).filter((k) => !k.archived)
          return [row(c, active, i, false), ...children.map((k, j) => row(k, children, j, true))]
        })}
      </ul>
      {archived.length > 0 && (
        <section className="mt-8">
          <h2 className="mb-2 px-3 text-[13px] font-semibold text-ink-3">Archiviert</h2>
          <p className="mb-3 px-3 text-[13px] text-ink-3">Erscheinen nicht mehr in der Erfassung; alte Buchungen behalten sie.</p>
          <ul className="space-y-2">
            {archived.map((c) => (
              <li key={c.id} className="flex items-center gap-3 rounded-tile bg-tile/60 p-3">
                <CategoryIcon icon={c.icon} color={tree.colorFor(c.id) ?? c.color} className="opacity-60" />
                <span className="flex-1 truncate text-[15px] text-ink-2">{tree.labelFor(c.id)}</span>
                {/* A child of an archived parent only becomes selectable again with its parent. */}
                {c.archived && !(c.parentId && tree.byId.get(c.parentId)?.archived) ? (
                  <Button size="sm" onClick={() => void save('categories', { ...strip(c), archived: false }, 'Kategorie wiederhergestellt')}>
                    <ArchiveRestore className="size-4" /> Wiederherstellen
                  </Button>
                ) : (
                  <span className="text-[12px] text-ink-3">Hauptkategorie zuerst wiederherstellen</span>
                )}
              </li>
            ))}
          </ul>
        </section>
      )}
      <Sheet open={editing !== null} onOpenChange={(o) => !o && setEditing(null)} title={editing === 'new' ? 'Neue Kategorie' : 'Kategorie bearbeiten'}>
        {editing !== null && <CategoryForm target={editing} defaultKind={kind} all={all} onDone={() => setEditing(null)} />}
      </Sheet>
    </div>
  )
}

const strip = ({ version: _v, ...rest }: Category) => rest

function CategoryForm({ target, defaultKind, all, onDone }: { target: Category | 'new'; defaultKind: Kind; all: Category[]; onDone(): void }) {
  const data = useData()
  const save = useSaver()
  const existing = target === 'new' ? null : target
  const [name, setName] = useState(existing?.name ?? '')
  const [icon, setIcon] = useState(existing?.icon ?? CATEGORY_SYMBOLS[0]!)
  const [color, setColor] = useState(existing?.color ?? CATEGORY_COLORS[8]!)
  const [kind, setKind] = useState<Kind>(existing?.kind ?? defaultKind)
  const [parentId, setParentId] = useState<string | null>(existing?.parentId ?? null)
  const problem = categoryNameProblem(name)
  const parent = parentId ? all.find((c) => c.id === parentId) : undefined
  const options = parentOptions(existing, all, kind)
  // Keep the current parent listed even if it is archived now.
  const parents = parent && !options.includes(parent) ? [parent, ...options] : options
  const budgetEffect = existing && parent ? moveBudgetEffect(existing, parent.id, [...data.budgets.values()]) : 'none'
  const symbols = CATEGORY_SYMBOLS.includes(icon) ? CATEGORY_SYMBOLS : [icon, ...CATEGORY_SYMBOLS]
  const colors = CATEGORY_COLORS.includes(color.toUpperCase()) ? CATEGORY_COLORS : [...CATEGORY_COLORS, color]

  async function submit(e: FormEvent) {
    e.preventDefault()
    if (problem) return
    onDone()
    if (!existing) await save('categories', newCategory({ name, icon, color, kind, parentId }, all, uuidv4()), 'Kategorie angelegt')
    else if (parentId !== (existing.parentId ?? null)) await save('categories', moveCategory({ ...existing, name: name.trim(), icon, color }, parentId, all), 'Kategorie verschoben')
    else await save('categories', { ...strip(existing), name: name.trim(), icon, color }, 'Kategorie gespeichert')
  }

  const plan = existing ? removalPlan(existing, [...data.transactions.values()], [...data.recurringRules.values()], all) : null

  async function remove() {
    if (!plan || plan.action === 'blocked') return
    onDone()
    for (const r of plan.records) if (!(await save(r.table, r.record as never))) return
    toast.success(plan.action === 'archive' ? 'Kategorie archiviert – sie bleibt in alten Buchungen sichtbar.' : 'Kategorie gelöscht')
  }

  return (
    <form onSubmit={submit} className="space-y-5">
      <div className="flex items-center gap-3">
        <CategoryIcon icon={icon} color={parent?.color ?? color} size="lg" />
        <div className="flex-1">
          <Field label="Name" error={problem === 'tooLong' ? 'Höchstens 40 Zeichen' : null}>
            {(id) => <Input id={id} value={name} onChange={(e) => setName(e.target.value)} placeholder="Haustier" autoFocus={!existing} />}
          </Field>
        </div>
      </div>
      {!existing && (
        <Segmented<Kind>
          label="Art"
          value={kind}
          onChange={(k) => {
            setKind(k)
            setParentId(null)
          }}
          options={[
            { value: 'expense', label: 'Ausgabe' },
            { value: 'income', label: 'Einnahme' },
          ]}
        />
      )}
      {(parents.length > 0 || parentId) && (
        <Field
          label="Gehört zu"
          hint={
            budgetEffect === 'moves'
              ? `Das Budget geht auf ${parent!.name} über.`
              : budgetEffect === 'deleted'
                ? `Das Budget dieser Kategorie wird gelöscht, weil ${parent!.name} schon eins hat.`
                : undefined
          }
        >
          {(id) => (
            <Select id={id} value={parentId ?? ''} onChange={(e) => setParentId(e.target.value || null)}>
              <option value="">Keine (Hauptkategorie)</option>
              {parents.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
            </Select>
          )}
        </Field>
      )}
      <fieldset>
        <legend className="mb-2 px-1 text-[13px] font-medium text-ink-2">Symbol</legend>
        <div className="grid grid-cols-6 gap-2 sm:grid-cols-8">
          {symbols.map((s) => {
            const Icon = iconFor(s)
            return (
              <button
                key={s}
                type="button"
                aria-label={s}
                aria-pressed={s === icon}
                onClick={() => setIcon(s)}
                className={cn('grid aspect-square place-items-center rounded-2xl transition', s === icon ? 'bg-ink text-on-ink' : 'bg-tile text-ink-2 hover:bg-tile-2')}
              >
                <Icon className="size-5" />
              </button>
            )
          })}
        </div>
      </fieldset>
      {/* A subcategory takes its main category's color. */}
      {!parent && (
        <fieldset>
          <legend className="mb-2 px-1 text-[13px] font-medium text-ink-2">Farbe</legend>
          <div className="grid grid-cols-6 gap-3">
            {colors.map((c) => (
              <button
                key={c}
                type="button"
                aria-label={`Farbe ${c}`}
                aria-pressed={c.toUpperCase() === color.toUpperCase()}
                onClick={() => setColor(c)}
                className={cn('aspect-square rounded-full transition', c.toUpperCase() === color.toUpperCase() && 'ring-4 ring-ink ring-offset-2 ring-offset-bg')}
                style={{ backgroundColor: c }}
              />
            ))}
          </div>
        </fieldset>
      )}
      <Button type="submit" variant="primary" size="lg" className="w-full" disabled={!!problem || !data.online}>
        Speichern
      </Button>
      {plan?.action === 'blocked' && (
        <Button variant="danger" size="lg" className="w-full" disabled>
          Erst Unterkategorien entfernen
        </Button>
      )}
      {existing && plan && plan.action !== 'blocked' && (
        <ConfirmButton
          label={plan?.action === 'archive' ? 'Archivieren' : 'Löschen'}
          question={
            plan?.action === 'archive'
              ? 'Die Kategorie hat Buchungen oder Regeln. Sie wird archiviert: nicht mehr in der Erfassung, alte Buchungen behalten sie.'
              : 'Kategorie und ihr Budget endgültig löschen?'
          }
          confirmLabel={plan?.action === 'archive' ? 'Archivieren' : 'Löschen'}
          onConfirm={() => void remove()}
        />
      )}
    </form>
  )
}
