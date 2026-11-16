import { Target } from 'lucide-react'
import { type FormEvent, useMemo, useState } from 'react'
import { useData } from '../../app/AppContext'
import { useMonthParam } from '../../app/useMonthParam'
import { useSaver } from '../../app/useSaver'
import { CategoryIcon } from '../../components/CategoryIcon'
import { MonthSwitcher } from '../../components/MonthSwitcher'
import { Button } from '../../components/ui/Button'
import { Field, Input } from '../../components/ui/Field'
import { EmptyState, PageHeader, Progress, Skeleton } from '../../components/ui/Misc'
import { Sheet } from '../../components/ui/Sheet'
import { Tile, TileLabel } from '../../components/ui/Tile'
import { budgetLevel } from '../../domain/analytics'
import { monthOf, today } from '../../domain/dates'
import { centsToInput, formatMoney, parseMoney } from '../../domain/money'
import { cn } from '../../lib/cn'
import { uuidv4 } from '../../lib/uuid'
import { type BudgetRow, budgetRecord, budgetRows, removedBudget } from './model'

export function Budgets() {
  const data = useData()
  const [month, setMonth] = useMonthParam()
  const [editing, setEditing] = useState<BudgetRow | null>(null)
  const rows = useMemo(
    () => budgetRows([...data.categories.values()], [...data.budgets.values()], [...data.transactions.values()], month),
    [data.categories, data.budgets, data.transactions, month],
  )

  if (!data.loaded) return <Skeleton className="mt-16 h-96 rounded-tile" />

  const { total } = rows
  const ratio = total.limitCents > 0 ? total.spentCents / total.limitCents : 0
  const level = budgetLevel(total.spentCents, total.limitCents)
  const left = total.limitCents - total.spentCents
  const isCurrent = month === monthOf(today())

  return (
    <>
      <PageHeader title="Budgets" subtitle="Monatslimits" actions={<MonthSwitcher month={month} onChange={setMonth} />} />
      {total.limitCents > 0 ? (
        <Tile className="mb-4">
          <TileLabel>{isCurrent ? 'Noch verfügbar' : left >= 0 ? 'Übrig geblieben' : 'Überschritten'}</TileLabel>
          <div className={cn('num mt-1 text-[40px] font-semibold leading-none tracking-[-0.04em]', left < 0 && 'text-neg')}>{formatMoney(Math.abs(left))}</div>
          <p className="mb-4 mt-2 text-[14px] text-ink-3">
            <span className="num">{formatMoney(total.spentCents)}</span> von <span className="num">{formatMoney(total.limitCents)}</span> ausgegeben
          </p>
          <Progress ratio={ratio} level={level} className="h-3" />
        </Tile>
      ) : (
        <Tile className="mb-4">
          <EmptyState icon={Target} title="Behalte Ausgaben im Blick" text="Lege für Kategorien ein Monatslimit fest. Ab 80 % warnt die Übersicht." />
        </Tile>
      )}

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
        {rows.items.map((r) => (
          <button key={r.category.id} onClick={() => setEditing(r)} className="text-left">
            <Tile className={cn('h-full transition hover:-translate-y-0.5 active:scale-[0.99]', !r.budget && 'bg-tile/60 shadow-none')}>
              <div className="flex items-center gap-3">
                <CategoryIcon icon={r.category.icon} color={r.category.color} />
                <div className="min-w-0 flex-1">
                  <div className="truncate text-[15px] font-semibold">{r.category.name}</div>
                  <div className="num text-[13px] text-ink-3">
                    {r.budget ? `${formatMoney(r.spentCents)} von ${formatMoney(r.budget.monthlyLimitCents)}` : `${formatMoney(r.spentCents)} ausgegeben`}
                  </div>
                </div>
                {r.progress ? (
                  <span className={cn('num text-[15px] font-semibold', r.progress.level === 'exceeded' ? 'text-neg' : r.progress.level === 'warning' ? 'text-warn' : 'text-ink-2')}>
                    {Math.round(r.progress.ratio * 100)} %
                  </span>
                ) : (
                  <span className="rounded-full bg-tile-2 px-3 py-1 text-[13px] font-medium text-ink-2">Limit setzen</span>
                )}
              </div>
              {r.progress && <Progress ratio={r.progress.ratio} level={r.progress.level} className="mt-4" />}
            </Tile>
          </button>
        ))}
      </div>

      <Sheet open={!!editing} onOpenChange={(o) => !o && setEditing(null)} title={editing ? `Budget: ${editing.category.name}` : 'Budget'}>
        {editing && <BudgetForm row={editing} onDone={() => setEditing(null)} />}
      </Sheet>
    </>
  )
}

function BudgetForm({ row, onDone }: { row: BudgetRow; onDone(): void }) {
  const save = useSaver()
  const { online } = useData()
  const [text, setText] = useState(row.budget ? centsToInput(row.budget.monthlyLimitCents) : '')
  const cents = parseMoney(text)
  const error = text.trim() && cents === null ? 'Betrag größer 0 eingeben, z. B. 250 oder 99,90' : null

  async function submit(e: FormEvent) {
    e.preventDefault()
    if (cents === null) return
    onDone()
    await save('budgets', budgetRecord(row.budget, row.category.id, cents, uuidv4()), 'Budget gespeichert')
  }

  async function remove() {
    if (!row.budget) return
    onDone()
    await save('budgets', removedBudget(row.budget), 'Budget entfernt')
  }

  return (
    <form onSubmit={submit} className="space-y-4">
      <Field label="Monatslimit in €" error={error}>
        {(id) => <Input id={id} inputMode="decimal" autoFocus placeholder="250,00" value={text} onChange={(e) => setText(e.target.value)} className="num text-2xl font-semibold" />}
      </Field>
      <Button type="submit" variant="primary" size="lg" className="w-full" disabled={cents === null || !online}>
        Speichern
      </Button>
      {row.budget && (
        <Button variant="danger" size="lg" className="w-full" onClick={remove}>
          Budget entfernen
        </Button>
      )}
    </form>
  )
}
