import { ChevronDown, Delete, Trash2 } from 'lucide-react'
import { AnimatePresence, motion } from 'motion/react'
import { createContext, type ReactNode, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import { useCategoryTree, useData, useMe } from '../../app/AppContext'
import { useSaver } from '../../app/useSaver'
import { CategoryIcon } from '../../components/CategoryIcon'
import { SubcategoryChips } from '../../components/SubcategoryChips'
import { Button } from '../../components/ui/Button'
import { Field, Input, Select } from '../../components/ui/Field'
import { Segmented } from '../../components/ui/Segmented'
import { Sheet } from '../../components/ui/Sheet'
import { rankCategories } from '../../domain/analytics'
import { appendDigit, deleteLast } from '../../domain/amountInput'
import { germanDate, today } from '../../domain/dates'
import { formatMoney } from '../../domain/money'
import type { Kind, Transaction, TransactionInput } from '../../domain/types'
import { cn } from '../../lib/cn'
import { uuidv4 } from '../../lib/uuid'
import { type Rhythm, RhythmPicker } from '../more/RhythmPicker'
import { rhythmLabel, type RuleDraft, ruleProblem, toRule } from '../more/rules'
import { type Draft, draftProblem, toTransaction } from './draft'

type Ctx = { openNew(): void; openEdit(tx: Transaction): void }
const EntryCtx = createContext<Ctx | null>(null)
export const useEntry = (): Ctx => {
  const c = useContext(EntryCtx)
  if (!c) throw new Error('useEntry outside EntryProvider')
  return c
}

export function EntryProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<{ open: boolean; editing: Transaction | null; key: number }>({ open: false, editing: null, key: 0 })
  const openNew = useCallback(() => setState((s) => ({ open: true, editing: null, key: s.key + 1 })), [])
  const openEdit = useCallback((tx: Transaction) => setState((s) => ({ open: true, editing: tx, key: s.key + 1 })), [])
  const ctx = useMemo(() => ({ openNew, openEdit }), [openNew, openEdit])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey) return
      if (e.target instanceof HTMLElement && e.target.closest('input, textarea, select, [role=dialog]')) return
      if (e.key === 'n' || e.key === 'N') {
        e.preventDefault()
        openNew()
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [openNew])

  return (
    <EntryCtx.Provider value={ctx}>
      {children}
      <Sheet
        open={state.open}
        onOpenChange={(open) => setState((s) => ({ ...s, open }))}
        title={state.editing ? 'Buchung bearbeiten' : 'Neue Buchung'}
        hideTitle={!state.editing}
        description="Betrag eingeben und Kategorie wählen"
      >
        <EntryForm key={state.key} editing={state.editing} onDone={() => setState((s) => ({ ...s, open: false }))} />
      </Sheet>
    </EntryCtx.Provider>
  )
}

const KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '00', '0', 'del'] as const

/** Rule built from the entry form („Wiederholen“): starts on the chosen date, no end. */
const ruleDraftFor = (d: Draft, r: Rhythm): RuleDraft => ({
  cents: d.cents,
  kind: d.kind,
  categoryId: d.categoryId,
  paidBy: d.paidBy,
  note: d.note,
  ...r,
  startDate: d.date,
  endDate: '',
})

function EntryForm({ editing, onDone }: { editing: Transaction | null; onDone(): void }) {
  const saveRecord = useSaver()
  const me = useMe()
  const data = useData()
  const [draft, setDraft] = useState<Draft>(() =>
    editing
      ? { cents: editing.amountCents, kind: editing.kind, categoryId: editing.categoryId, date: editing.date, paidBy: editing.paidBy, note: editing.note ?? '' }
      : { cents: 0, kind: 'expense', categoryId: '', date: today(), paidBy: me.id, note: '' },
  )
  const [details, setDetails] = useState(!!editing)
  /** New entries only: when set, saving creates a recurring rule starting at the chosen date. */
  const [repeat, setRepeat] = useState<Rhythm | null>(null)
  const set = (patch: Partial<Draft>) => setDraft((d) => ({ ...d, ...patch }))

  const tree = useCategoryTree()
  // Ranked per main category: bookings on a subcategory count for its parent.
  const transactions = useMemo(() => [...data.transactions.values()].map((t) => ({ ...t, categoryId: tree.rootOf(t.categoryId) })), [data.transactions, tree])
  /** Main categories only; subcategories are picked with the chips below. */
  const categories = useMemo(() => {
    const ranked = rankCategories([...data.categories.values()].filter((c) => !c.parentId), transactions, draft.kind, today())
    // When editing, keep the (possibly archived) current main category selectable.
    const current = editing ? data.categories.get(tree.rootOf(editing.categoryId)) : undefined
    return current && current.kind === draft.kind && !ranked.includes(current) ? [current, ...ranked] : ranked
  }, [data.categories, transactions, draft.kind, editing, tree])
  const members = useMemo(() => [...data.users.values()].sort((a, b) => a.displayName.localeCompare(b.displayName)), [data.users])

  // Desktop: type the amount on the keyboard.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLElement && e.target.closest('input, textarea, select')) return
      if (/^\d$/.test(e.key)) set({ cents: appendDigit(draft.cents, Number(e.key)) })
      else if (e.key === 'Backspace') set({ cents: deleteLast(draft.cents) })
      else return
      e.preventDefault()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  })

  function press(k: (typeof KEYS)[number]) {
    if (k === 'del') set({ cents: deleteLast(draft.cents) })
    else for (const ch of k) setDraft((d) => ({ ...d, cents: appendDigit(d.cents, Number(ch)) }))
  }

  function persist(record: TransactionInput, message: string) {
    onDone()
    void saveRecord('transactions', record, {
      message,
      description: `${formatMoney(record.amountCents)} · ${tree.byId.has(record.categoryId) ? tree.labelFor(record.categoryId) : ''}`,
      undo: editing ? undefined : { ...record, deleted: true },
    })
  }

  function save(categoryId = draft.categoryId) {
    const d = { ...draft, categoryId }
    if (draftProblem(d)) return
    if (editing) void persist(toTransaction(d, editing.id, editing.recurringRuleId), 'Gespeichert')
    else if (repeat) saveRule(d, repeat)
    else void persist(toTransaction(d, uuidv4()), 'Gebucht')
  }

  /** The server books the first occurrence itself (at once if the date is today or earlier). */
  function saveRule(d: Draft, r: Rhythm) {
    const ruleDraft = ruleDraftFor(d, r)
    if (ruleProblem(ruleDraft)) return
    onDone()
    void saveRecord('recurringRules', toRule(ruleDraft, uuidv4()), {
      message: 'Wiederkehrend angelegt',
      description: `${rhythmLabel(r.frequency, r.interval)} · erste Buchung am ${germanDate(d.date)}`,
    })
  }

  function remove() {
    if (!editing) return
    onDone()
    const { version: _v, ...record } = editing
    void saveRecord('transactions', { ...record, deleted: true }, { message: 'Buchung gelöscht', undo: record })
  }

  const problem = draftProblem(draft)
  const offline = !data.online
  const repeatInvalid = repeat !== null && ruleProblem(ruleDraftFor(draft, repeat)) !== null
  const amountReady = draft.cents > 0 && !offline
  /** Category taps only select (no immediate save). */
  const selecting = !!editing || details
  const mainId = draft.categoryId ? tree.rootOf(draft.categoryId) : ''
  // The current value counts too, so editing a booking on an archived subcategory still shows its chip.
  const hasSubcategories = (id: string) => tree.childrenOf(id).some((c) => tree.isSelectable(c) || c.id === draft.categoryId)

  function pickMain(id: string) {
    // Picking another main category starts at „Allgemein“ (the main category itself).
    if (id === mainId) return
    if (selecting || hasSubcategories(id)) set({ categoryId: id })
    else save(id)
  }

  return (
    <div className="space-y-5">
      <div className="flex flex-col items-center gap-4">
        <Segmented<Kind>
          label="Art"
          value={draft.kind}
          onChange={(kind) => set({ kind, categoryId: kind === draft.kind ? draft.categoryId : '' })}
          options={[
            { value: 'expense', label: 'Ausgabe' },
            { value: 'income', label: 'Einnahme' },
          ]}
          className="w-full max-w-xs"
        />
        <output aria-live="polite" aria-label="Betrag" className={cn('num block text-center text-[56px] font-semibold leading-none tracking-[-0.04em]', !amountReady && 'text-ink-3')}>
          <AnimatePresence mode="popLayout" initial={false}>
            <motion.span key={draft.cents} initial={{ y: 8, opacity: 0.4 }} animate={{ y: 0, opacity: 1 }} transition={{ duration: 0.12 }} className="inline-block">
              {formatMoney(draft.cents)}
            </motion.span>
          </AnimatePresence>
        </output>
      </div>

      <div className="grid grid-cols-3 gap-2" role="group" aria-label="Ziffernblock">
        {KEYS.map((k) => (
          <button
            key={k}
            type="button"
            onClick={() => press(k)}
            aria-label={k === 'del' ? 'Letzte Ziffer löschen' : k}
            className="grid h-14 place-items-center rounded-2xl bg-tile text-2xl font-medium shadow-tile transition active:scale-95 active:bg-tile-2"
          >
            {k === 'del' ? <Delete className="size-6 text-ink-2" /> : k}
          </button>
        ))}
      </div>

      <section aria-label="Kategorie">
        <p className={cn('mb-2 px-1 text-[13px] font-medium', offline ? 'text-warn' : 'text-ink-3')}>
          {offline ? 'Keine Verbindung zur NAS – Speichern gerade nicht möglich' : editing ? 'Kategorie' : amountReady ? 'Kategorie antippen zum Speichern' : 'Erst Betrag eingeben'}
        </p>
        <div className={cn('grid grid-cols-4 gap-2 transition-opacity sm:grid-cols-5', !amountReady && !editing && 'pointer-events-none opacity-40')}>
          {categories.map((c) => {
            const selected = c.id === mainId
            return (
              <button
                key={c.id}
                type="button"
                disabled={offline || (!amountReady && !editing)}
                onClick={() => pickMain(c.id)}
                aria-pressed={selecting || hasSubcategories(c.id) ? selected : undefined}
                className={cn(
                  'flex flex-col items-center gap-1.5 rounded-2xl px-1 py-2.5 transition active:scale-95',
                  selected ? 'bg-tile shadow-tile ring-2 ring-ink' : 'hover:bg-tile',
                )}
              >
                <CategoryIcon icon={c.icon} color={tree.colorFor(c.id) ?? c.color} />
                <span lang="de" className="line-clamp-2 w-full hyphens-auto break-words text-center text-[12px] font-medium leading-tight text-ink-2">{c.name}</span>
              </button>
            )
          })}
        </div>
        {mainId && hasSubcategories(mainId) && (
          // A fieldset only to disable all chips at once; the chip row names itself.
          <fieldset disabled={offline || (!amountReady && !editing)} className="mt-4 disabled:opacity-40">
            <p className="mb-2 px-1 text-[13px] font-medium text-ink-3">{selecting ? 'Unterkategorie' : 'Unterkategorie antippen zum Speichern'}</p>
            <SubcategoryChips parentId={mainId} value={selecting ? draft.categoryId : ''} tree={tree} onChange={(id) => (selecting ? set({ categoryId: id }) : save(id))} />
          </fieldset>
        )}
      </section>

      {!editing && (
        <button
          type="button"
          onClick={() => {
            // A hidden repeat setting would turn the next category tap into a rule unnoticed.
            if (details) setRepeat(null)
            setDetails(!details)
          }} className="flex w-full items-center justify-between rounded-2xl bg-tile px-4 py-3 text-[15px] font-medium shadow-tile">
          Details
          <ChevronDown className={cn('size-5 text-ink-3 transition-transform', details && 'rotate-180')} />
        </button>
      )}
      <AnimatePresence initial={false}>
        {details && (
          <motion.div initial={{ height: 0, opacity: 0 }} animate={{ height: 'auto', opacity: 1 }} exit={{ height: 0, opacity: 0 }} className="overflow-hidden">
            <div className="grid gap-4 pt-1 sm:grid-cols-2">
              {!editing && (
                <div className="sm:col-span-2">
                  <RhythmPicker value={repeat} onChange={setRepeat} allowNone />
                </div>
              )}
              <Field label="Datum" error={problem === 'date' ? 'Ungültiges Datum' : null}>
                {(id) => <Input id={id} type="date" value={draft.date} onChange={(e) => set({ date: e.target.value })} />}
              </Field>
              <Field label="Bezahlt von">
                {(id) => (
                  <Select id={id} value={draft.paidBy} onChange={(e) => set({ paidBy: e.target.value })}>
                    {members.map((m) => (
                      <option key={m.id} value={m.id}>
                        {m.displayName}
                      </option>
                    ))}
                    {!members.some((m) => m.id === draft.paidBy) && <option value={draft.paidBy}>{data.names.get(draft.paidBy) ?? 'Unbekannt'}</option>}
                  </Select>
                )}
              </Field>
              <div className="sm:col-span-2">
                <Field label="Notiz" error={problem === 'note' ? 'Höchstens 200 Zeichen' : null}>
                  {(id) => <Input id={id} value={draft.note} placeholder="Wochenmarkt" onChange={(e) => set({ note: e.target.value })} />}
                </Field>
              </div>
            </div>
            <Button variant="primary" size="lg" className="mt-5 w-full" disabled={!!problem || offline || repeatInvalid} onClick={() => save()}>
              Speichern
            </Button>
            {editing && (
              <Button variant="danger" size="lg" className="mt-2 w-full" disabled={offline} onClick={remove}>
                <Trash2 className="size-5" /> Löschen
              </Button>
            )}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  )
}
