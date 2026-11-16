import { CalendarClock, Plus } from 'lucide-react'
import { type FormEvent, useMemo, useState } from 'react'
import { useData, useMe } from '../../app/AppContext'
import { useSaver } from '../../app/useSaver'
import { CategoryIcon } from '../../components/CategoryIcon'
import { Button } from '../../components/ui/Button'
import { ConfirmButton } from '../../components/ui/ConfirmButton'
import { Field, Input, Select } from '../../components/ui/Field'
import { BackLink, EmptyState, PageHeader } from '../../components/ui/Misc'
import { Segmented } from '../../components/ui/Segmented'
import { Sheet } from '../../components/ui/Sheet'
import { Tile } from '../../components/ui/Tile'
import { germanDate, today } from '../../domain/dates'
import { centsToInput, formatSigned, parseMoney } from '../../domain/money'
import type { Frequency, Kind, RecurringRule } from '../../domain/types'
import { uuidv4 } from '../../lib/uuid'
import { type RuleDraft, ruleProblem, ruleSchedule, toRule } from './rules'

export function Recurring() {
  const data = useData()
  const [editing, setEditing] = useState<RecurringRule | 'new' | null>(null)
  const rules = useMemo(() => [...data.recurringRules.values()].sort((a, b) => (a.nextDueDate < b.nextDueDate ? -1 : 1)), [data.recurringRules])
  const now = today()

  return (
    <div className="mx-auto max-w-2xl">
      <BackLink />
      <PageHeader
        title="Wiederkehrend"
        subtitle="Daueraufträge und Abos"
        actions={
          <Button variant="primary" size="sm" onClick={() => setEditing('new')}>
            <Plus className="size-4" /> Neu
          </Button>
        }
      />
      {rules.length === 0 ? (
        <Tile>
          <EmptyState icon={CalendarClock} title="Miete, Gehalt, Abos" text="Lege fest, was regelmäßig anfällt. Die NAS bucht es dann automatisch am Fälligkeitstag." action={<Button variant="primary" onClick={() => setEditing('new')}>Regel anlegen</Button>} />
        </Tile>
      ) : (
        <ul className="space-y-2">
          {rules.map((r) => {
            const c = data.categories.get(r.categoryId)
            const ended = r.endDate !== null && r.nextDueDate > r.endDate
            return (
              <li key={r.id}>
                <button onClick={() => setEditing(r)} className="flex w-full items-center gap-3 rounded-tile bg-tile p-4 text-left shadow-tile transition active:scale-[0.99]">
                  <CategoryIcon icon={c?.icon ?? ''} color={c?.color ?? '#999'} />
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-[15px] font-medium">{r.note || c?.name || 'Ohne Kategorie'}</span>
                    <span className="block truncate text-[13px] text-ink-3">{ruleSchedule(r.frequency, r.startDate)}</span>
                    <span className="block truncate text-[13px] text-ink-3">
                      {ended ? 'Beendet' : r.nextDueDate <= now ? 'Heute fällig' : `Nächste Buchung am ${germanDate(r.nextDueDate)}`}
                    </span>
                  </span>
                  <span className={`num text-[15px] font-semibold ${r.kind === 'income' ? 'text-pos' : ''}`}>{formatSigned(r.amountCents, r.kind)}</span>
                </button>
              </li>
            )
          })}
        </ul>
      )}
      <Sheet open={editing !== null} onOpenChange={(o) => !o && setEditing(null)} title={editing === 'new' ? 'Neue Regel' : 'Regel bearbeiten'}>
        {editing !== null && <RuleForm target={editing} onDone={() => setEditing(null)} />}
      </Sheet>
    </div>
  )
}

const PROBLEM_TEXT: Record<string, string> = {
  startDate: 'Gültiges Datum ab 01.01.2000',
  endDate: 'Muss am oder nach dem Start liegen',
  note: 'Höchstens 200 Zeichen',
}

function RuleForm({ target, onDone }: { target: RecurringRule | 'new'; onDone(): void }) {
  const data = useData()
  const me = useMe()
  const save = useSaver()
  const existing = target === 'new' ? null : target
  const [amount, setAmount] = useState(existing ? centsToInput(existing.amountCents) : '')
  const [d, setD] = useState<Omit<RuleDraft, 'cents'>>(() => ({
    kind: existing?.kind ?? 'expense',
    categoryId: existing?.categoryId ?? '',
    paidBy: existing?.paidBy ?? me.id,
    note: existing?.note ?? '',
    frequency: existing?.frequency ?? 'monthly',
    startDate: existing?.startDate ?? today(),
    endDate: existing?.endDate ?? '',
  }))
  const set = (p: Partial<typeof d>) => setD((x) => ({ ...x, ...p }))
  const draft: RuleDraft = { ...d, cents: parseMoney(amount) ?? 0 }
  const problem = ruleProblem(draft)
  const categories = [...data.categories.values()].filter((c) => c.kind === d.kind && (!c.archived || c.id === d.categoryId)).sort((a, b) => a.sortOrder - b.sortOrder)
  const members = [...data.users.values()]

  async function submit(e: FormEvent) {
    e.preventDefault()
    if (problem) return
    onDone()
    await save('recurringRules', toRule(draft, existing?.id ?? uuidv4()), 'Regel gespeichert')
  }

  async function remove() {
    if (!existing) return
    onDone()
    // Delete the stored rule as it is, independent of unsaved (possibly invalid) form edits.
    const { version: _v, nextDueDate: _n, ...stored } = existing
    await save('recurringRules', { ...stored, deleted: true }, 'Regel gelöscht')
  }

  return (
    <form onSubmit={submit} className="space-y-4">
      <Segmented<Kind>
        label="Art"
        value={d.kind}
        onChange={(kind) => set({ kind, categoryId: kind === d.kind ? d.categoryId : '' })}
        options={[
          { value: 'expense', label: 'Ausgabe' },
          { value: 'income', label: 'Einnahme' },
        ]}
      />
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Betrag in €" error={amount.trim() && problem === 'amount' ? 'Betrag größer 0 eingeben' : null}>
          {(id) => <Input id={id} inputMode="decimal" placeholder="49,99" value={amount} onChange={(e) => setAmount(e.target.value)} className="num font-semibold" />}
        </Field>
        <Field label="Kategorie">
          {(id) => (
            <Select id={id} value={d.categoryId} onChange={(e) => set({ categoryId: e.target.value })}>
              <option value="">Bitte wählen</option>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </Select>
          )}
        </Field>
      </div>
      <Segmented<Frequency>
        label="Rhythmus"
        value={d.frequency}
        onChange={(frequency) => set({ frequency })}
        options={[
          { value: 'weekly', label: 'Wöchentlich' },
          { value: 'monthly', label: 'Monatlich' },
          { value: 'yearly', label: 'Jährlich' },
        ]}
      />
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Start" error={problem === 'startDate' ? PROBLEM_TEXT.startDate : null} hint={problem !== 'startDate' ? ruleSchedule(d.frequency, d.startDate) : undefined}>
          {(id) => <Input id={id} type="date" value={d.startDate} onChange={(e) => set({ startDate: e.target.value })} />}
        </Field>
        <Field label="Ende (optional)" error={problem === 'endDate' ? PROBLEM_TEXT.endDate : null}>
          {(id) => <Input id={id} type="date" value={d.endDate} onChange={(e) => set({ endDate: e.target.value })} />}
        </Field>
        <Field label="Bezahlt von">
          {(id) => (
            <Select id={id} value={d.paidBy} onChange={(e) => set({ paidBy: e.target.value })}>
              {members.map((m) => (
                <option key={m.id} value={m.id}>
                  {m.displayName}
                </option>
              ))}
              {!members.some((m) => m.id === d.paidBy) && <option value={d.paidBy}>{data.names.get(d.paidBy) ?? 'Unbekannt'}</option>}
            </Select>
          )}
        </Field>
        <Field label="Notiz" error={problem === 'note' ? PROBLEM_TEXT.note : null}>
          {(id) => <Input id={id} placeholder="Miete" value={d.note} onChange={(e) => set({ note: e.target.value })} />}
        </Field>
      </div>
      {existing && <p className="px-1 text-[13px] text-ink-3">Nächster Termin: {germanDate(existing.nextDueDate)} (berechnet die NAS)</p>}
      <Button type="submit" variant="primary" size="lg" className="w-full" disabled={!!problem || !data.online}>
        Speichern
      </Button>
      {existing && (
        <ConfirmButton
          label="Regel löschen"
          question="Regel löschen? Bereits erzeugte Buchungen bleiben erhalten."
          confirmLabel="Löschen"
          onConfirm={() => void remove()}
        />
      )}
    </form>
  )
}
