import { ListX, Search, X } from 'lucide-react'
import { useMemo, useState } from 'react'
import { useSearchParams } from 'react-router'
import { useCategoryTree, useData } from '../../app/AppContext'
import { TransactionRow } from '../../components/TransactionRow'
import { Button } from '../../components/ui/Button'
import { ChipSelect } from '../../components/ui/ChipSelect'
import { EmptyState, PageHeader, Skeleton } from '../../components/ui/Misc'
import { Tile, TileLabel } from '../../components/ui/Tile'
import { addMonths, dayHeading, isValidDay, monthOf, monthTitle, today } from '../../domain/dates'
import { formatMoney } from '../../domain/money'
import type { Kind } from '../../domain/types'
import { cn } from '../../lib/cn'
import { useEntry } from '../quickEntry/EntrySheet'
import { emptyFilter, filterActive, sections, type TxFilter } from './list'

const PAGE = 40

export function Transactions() {
  const data = useData()
  const { openEdit, openNew } = useEntry()
  const [params, setParams] = useSearchParams()
  const monthParam = params.get('monat')
  const [filter, setFilter] = useState<TxFilter>(() => ({ ...emptyFilter, month: monthParam && isValidDay(`${monthParam}-01`) ? monthParam : null }))
  const [shown, setShown] = useState(PAGE)
  const set = (patch: Partial<TxFilter>) => {
    setFilter((f) => ({ ...f, ...patch }))
    setShown(PAGE)
    if ('month' in patch) setParams(patch.month ? { monat: patch.month } : {}, { replace: true })
  }

  const txs = useMemo(() => [...data.transactions.values()], [data.transactions])
  const tree = useCategoryTree()
  const list = useMemo(() => sections(txs, filter, tree), [txs, filter, tree])
  const totals = useMemo(() => {
    let income = 0
    let expense = 0
    for (const s of list) {
      for (const t of s.items) {
        if (t.kind === 'income') income += t.amountCents
        else expense += t.amountCents
      }
    }
    return { income, expense, count: list.reduce((n, s) => n + s.items.length, 0) }
  }, [list])

  /** Main categories, each followed by its subcategories. */
  const categories = useMemo(
    () =>
      [...data.categories.values()]
        .filter((c) => (!filter.kind || c.kind === filter.kind) && tree.rootOf(c.id) === c.id)
        .sort((a, b) => a.kind.localeCompare(b.kind) || a.sortOrder - b.sortOrder || a.name.localeCompare(b.name))
        .flatMap((c) => [c, ...tree.childrenOf(c.id)]),
    [data.categories, filter.kind, tree],
  )
  const members = [...data.users.values()].sort((a, b) => a.displayName.localeCompare(b.displayName))
  const months = useMemo(() => Array.from({ length: 24 }, (_, i) => addMonths(monthOf(today()), -i)), [])
  const anyFilter = filterActive(filter) || filter.month !== null || filter.search.trim() !== ''

  if (!data.loaded) return <Skeleton className="mt-16 h-96 rounded-tile" />

  return (
    <>
      <PageHeader title="Buchungen" subtitle={`${totals.count} ${totals.count === 1 ? 'Eintrag' : 'Einträge'}`} />
      <div className="lg:grid lg:grid-cols-[minmax(0,1fr)_300px] lg:gap-6">
        <div className="min-w-0">
          <div className="relative mb-3">
            <Search className="pointer-events-none absolute left-4 top-1/2 size-5 -translate-y-1/2 text-ink-3" />
            <input
              type="search"
              value={filter.search}
              onChange={(e) => set({ search: e.target.value })}
              placeholder="Notiz oder Kategorie suchen"
              aria-label="Suchen"
              className="h-12 w-full rounded-full bg-tile pl-12 pr-4 text-[16px] shadow-tile outline-none ring-accent/40 placeholder:text-ink-3 focus:ring-2"
            />
          </div>
          <div className="-mx-4 mb-5 flex gap-2 overflow-x-auto px-4 pb-1 [scrollbar-width:none] sm:mx-0 sm:flex-wrap sm:px-0">
            <ChipSelect
              label="Art"
              value={filter.kind}
              onChange={(v) => set({ kind: v as Kind | null, categoryId: null })}
              options={[
                { value: 'expense', label: 'Ausgaben' },
                { value: 'income', label: 'Einnahmen' },
              ]}
            />
            <ChipSelect label="Monat" value={filter.month} onChange={(v) => set({ month: v })} options={months.map((m) => ({ value: m, label: monthTitle(m) }))} />
            <ChipSelect label="Kategorie" value={filter.categoryId} onChange={(v) => set({ categoryId: v })} options={categories.map((c) => ({ value: c.id, label: tree.isSelectable(c) ? tree.labelFor(c.id) : `${tree.labelFor(c.id)} (archiviert)` }))} />
            {members.length > 1 && <ChipSelect label="Person" value={filter.paidBy} onChange={(v) => set({ paidBy: v })} options={members.map((m) => ({ value: m.id, label: m.displayName }))} />}
            {anyFilter && (
              <button onClick={() => set({ ...emptyFilter })} className="inline-flex h-9 shrink-0 items-center gap-1 rounded-full px-3 text-[14px] font-medium text-accent">
                <X className="size-4" /> Zurücksetzen
              </button>
            )}
          </div>

          {list.length === 0 ? (
            <Tile>
              {txs.length === 0 ? (
                <EmptyState icon={ListX} title="Noch keine Buchungen" text="Erfasse deine erste Ausgabe – sie erscheint dann hier." action={<Button variant="primary" onClick={openNew}>Buchung erfassen</Button>} />
              ) : (
                <EmptyState icon={ListX} title="Nichts gefunden" text="Keine Buchung passt zu Suche und Filtern." action={<Button onClick={() => set({ ...emptyFilter })}>Filter zurücksetzen</Button>} />
              )}
            </Tile>
          ) : (
            <div className="space-y-5">
              {list.slice(0, shown).map((s) => (
                <section key={s.day} aria-label={dayHeading(s.day)}>
                  <div className="sticky top-0 z-10 -mx-1 mb-1.5 flex items-baseline justify-between bg-bg/90 px-2 py-1.5 backdrop-blur">
                    <h2 className="text-[13px] font-semibold text-ink-2">{dayHeading(s.day)}</h2>
                    <span className={cn('num text-[13px] font-medium', s.netCents > 0 ? 'text-pos' : 'text-ink-3')}>
                      {s.netCents > 0 ? '+' : s.netCents < 0 ? '−' : ''}
                      {formatMoney(Math.abs(s.netCents))}
                    </span>
                  </div>
                  <Tile className="p-2">
                    {s.items.map((t) => (
                      <TransactionRow key={t.id} tx={t} category={data.categories.get(t.categoryId)} label={tree.byId.has(t.categoryId) ? tree.labelFor(t.categoryId) : undefined} payerName={data.names.get(t.paidBy)} showPayer={members.length > 1} onClick={() => openEdit(t)} />
                    ))}
                  </Tile>
                </section>
              ))}
              {shown < list.length && (
                <div className="flex justify-center">
                  <Button onClick={() => setShown((n) => n + PAGE)}>Ältere anzeigen</Button>
                </div>
              )}
            </div>
          )}
        </div>

        <aside className="hidden lg:block">
          <div className="sticky top-4 space-y-4">
            <Tile>
              <TileLabel>{anyFilter ? 'Auswahl' : 'Alle Buchungen'}</TileLabel>
              <dl className="mt-3 space-y-3 text-[14px]">
                <div className="flex justify-between">
                  <dt className="text-ink-3">Einnahmen</dt>
                  <dd className="num font-semibold text-pos">{formatMoney(totals.income)}</dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-ink-3">Ausgaben</dt>
                  <dd className="num font-semibold">{formatMoney(totals.expense)}</dd>
                </div>
                <div className="flex justify-between border-t border-line pt-3">
                  <dt className="font-medium">Saldo</dt>
                  <dd className="num text-lg font-semibold">{formatMoney(totals.income - totals.expense)}</dd>
                </div>
              </dl>
            </Tile>
            <p className="px-2 text-[13px] text-ink-3">Tippe auf eine Buchung, um sie zu bearbeiten oder zu löschen.</p>
          </div>
        </aside>
      </div>
    </>
  )
}
