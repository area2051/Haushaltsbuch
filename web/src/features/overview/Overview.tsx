import { ArrowDownRight, ArrowUpRight, ChevronDown, PiggyBank, Sparkles } from 'lucide-react'
import { useMemo, useState } from 'react'
import { Link } from 'react-router'
import { Area, AreaChart, Bar, BarChart, Cell, Pie, PieChart, ResponsiveContainer, Tooltip, XAxis } from 'recharts'
import { useCategoryTree, useData, useMe } from '../../app/AppContext'
import { CategoryIcon } from '../../components/CategoryIcon'
import { MonthSwitcher } from '../../components/MonthSwitcher'
import { TransactionRow } from '../../components/TransactionRow'
import { Button } from '../../components/ui/Button'
import { AnimatedNumber, EmptyState, PageHeader, Progress, Skeleton } from '../../components/ui/Misc'
import { Tile, TileLabel } from '../../components/ui/Tile'
import { categoryTrend, cumulativeDailyExpenses, monthlyTrend } from '../../domain/analytics'
import { useMonthParam } from '../../app/useMonthParam'
import { daysInMonth, monthOf, monthShort, today } from '../../domain/dates'
import { formatMoney } from '../../domain/money'
import { cn } from '../../lib/cn'
import { useEntry } from '../quickEntry/EntrySheet'
import { OTHERS_COLOR, overviewModel } from './model'

const short = new Intl.NumberFormat('de-DE', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 })
const fmtShort = (cents: number) => short.format(Math.round(cents / 100))

function greeting(): string {
  const h = new Date().getHours()
  return h < 11 ? 'Guten Morgen' : h < 18 ? 'Hallo' : 'Guten Abend'
}

export function Overview() {
  const me = useMe()
  const data = useData()
  const { openNew, openEdit } = useEntry()
  const [month, setMonth] = useMonthParam()
  const tree = useCategoryTree()
  /** Main categories whose subcategory breakdown is shown. */
  const [expanded, setExpanded] = useState<ReadonlySet<string>>(() => new Set())
  const toggle = (id: string) =>
    setExpanded((prev) => {
      const next = new Set(prev)
      if (!next.delete(id)) next.add(id)
      return next
    })

  const txs = useMemo(() => [...data.transactions.values()], [data.transactions])
  const model = useMemo(
    () =>
      overviewModel({
        txs,
        categories: [...data.categories.values()],
        // Includes removed members, so their past spending keeps a name.
        members: [...data.names].map(([id, displayName]) => ({ id, displayName })),
        budgets: [...data.budgets.values()],
        month,
      }),
    [txs, data.categories, data.names, data.budgets, month],
  )
  const trend = useMemo(() => monthlyTrend(txs, month, 12), [txs, month])
  const catTrend = useMemo(() => categoryTrend(txs, month, 6, 5, tree.rootOf), [txs, month, tree])
  // Whole month on the x axis; in the current month the line stops today.
  const spark = useMemo(() => {
    const now = today()
    const lastShown = monthOf(now) === month ? Number(now.slice(8, 10)) : daysInMonth(month)
    return cumulativeDailyExpenses(txs, month, daysInMonth(month)).map((v, i) => ({ d: i + 1, v: i < lastShown ? v : null }))
  }, [txs, month])
  const prev = trend.at(-2)
  const firstName = me.displayName.split(' ')[0]

  if (!data.loaded) return <OverviewSkeleton />

  const s = model.summary
  const expenseDelta = prev && prev.expenseCents > 0 ? (s.expenseCents - prev.expenseCents) / prev.expenseCents : null
  const multiplePeople = data.users.size > 1

  return (
    <>
      <PageHeader title={`${greeting()}, ${firstName}`} subtitle="Übersicht" actions={<MonthSwitcher month={month} onChange={setMonth} />} />
      {!model.hasTransactions && txs.length === 0 ? (
        <Tile>
          <EmptyState
            icon={Sparkles}
            title="Deine erste Buchung"
            text="Tippe auf Plus, gib den Betrag ein und wähle eine Kategorie. Das dauert keine drei Sekunden."
            action={
              <Button variant="primary" onClick={openNew}>
                Buchung erfassen
              </Button>
            }
          />
        </Tile>
      ) : (
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-6">
          {/* Balance */}
          <Tile className="relative overflow-hidden md:col-span-2 lg:col-span-4">
            <TileLabel>Saldo</TileLabel>
            <div className={cn('num mt-1 text-[44px] font-semibold leading-none tracking-[-0.045em] lg:text-[56px]', s.balanceCents < 0 && 'text-neg')}>
              <AnimatedNumber value={s.balanceCents} format={formatMoney} />
            </div>
            <div className="mt-4 flex flex-wrap gap-2">
              <span className="inline-flex items-center gap-1.5 rounded-full bg-pos-soft px-3 py-1.5 text-[13px] font-semibold text-pos">
                <ArrowUpRight className="size-4" /> <span className="num">{formatMoney(s.incomeCents)}</span>
              </span>
              <span className="inline-flex items-center gap-1.5 rounded-full bg-tile-2 px-3 py-1.5 text-[13px] font-semibold text-ink-2">
                <ArrowDownRight className="size-4" /> <span className="num">{formatMoney(s.expenseCents)}</span>
              </span>
              {expenseDelta !== null && (
                <span className="inline-flex items-center rounded-full px-2 py-1.5 text-[13px] text-ink-3">
                  Ausgaben {expenseDelta >= 0 ? '+' : '−'}
                  {Math.abs(Math.round(expenseDelta * 100))} % ggü. Vormonat
                </span>
              )}
            </div>
            <div className="-mx-5 -mb-5 mt-4 h-20" aria-hidden>
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={spark} margin={{ top: 4, right: 0, bottom: 0, left: 0 }}>
                  <defs>
                    <linearGradient id="spark" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="var(--accent)" stopOpacity={0.28} />
                      <stop offset="100%" stopColor="var(--accent)" stopOpacity={0} />
                    </linearGradient>
                  </defs>
                  <Area type="monotone" dataKey="v" stroke="var(--accent)" strokeWidth={2} fill="url(#spark)" isAnimationActive />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          </Tile>

          {/* Donut */}
          <Tile className="md:row-span-2 lg:col-span-2">
            <TileLabel>Ausgaben nach Kategorie</TileLabel>
            {model.slices.length === 0 ? (
              <p className="py-10 text-center text-[14px] text-ink-3">Keine Ausgaben in diesem Monat.</p>
            ) : (
              <>
                <div className="relative mx-auto mt-2 aspect-square w-full max-w-[220px]">
                  <ResponsiveContainer width="100%" height="100%">
                    <PieChart>
                      <Pie data={model.slices} dataKey="cents" nameKey="name" innerRadius="70%" outerRadius="100%" paddingAngle={2} cornerRadius={6} stroke="none" startAngle={90} endAngle={-270}>
                        {model.slices.map((sl) => (
                          <Cell key={sl.id} fill={sl.color} onClick={sl.children.length > 0 ? () => toggle(sl.id) : undefined} className={cn(sl.children.length > 0 && 'cursor-pointer')} />
                        ))}
                      </Pie>
                      <Tooltip content={<ChartTip />} />
                    </PieChart>
                  </ResponsiveContainer>
                  <div className="pointer-events-none absolute inset-0 grid place-items-center text-center">
                    <div>
                      <div className="text-[12px] font-medium text-ink-3">Ausgaben</div>
                      <div className="num text-xl font-semibold">{fmtShort(s.expenseCents)}</div>
                    </div>
                  </div>
                </div>
                <ul className="mt-4 space-y-2.5">
                  {model.slices.map((sl) => {
                    const share = (cents: number) => `${Math.round((cents / s.expenseCents) * 100)} %`
                    const open = expanded.has(sl.id)
                    const row = (
                      <>
                        <span className="size-2.5 shrink-0 rounded-full" style={{ backgroundColor: sl.color }} />
                        <span className="flex min-w-0 flex-1 items-center gap-1">
                          <span className="truncate font-medium">{sl.name}</span>
                          {sl.children.length > 0 && <ChevronDown aria-hidden className={cn('size-4 shrink-0 text-ink-3 transition-transform', open && 'rotate-180')} />}
                        </span>
                        <span className="text-ink-3">{share(sl.cents)}</span>
                        <span className="num w-20 text-right font-semibold">{fmtShort(sl.cents)}</span>
                      </>
                    )
                    if (sl.children.length === 0) {
                      return (
                        <li key={sl.id} className="flex items-center gap-3 text-[14px]">
                          {row}
                        </li>
                      )
                    }
                    return (
                      <li key={sl.id}>
                        <button
                          type="button"
                          aria-expanded={open}
                          aria-controls={`breakdown-${sl.id}`}
                          onClick={() => toggle(sl.id)}
                          className="-mx-1.5 flex w-[calc(100%+0.75rem)] items-center gap-3 rounded-xl px-1.5 py-0.5 text-left text-[14px] transition hover:bg-tile-2"
                        >
                          {row}
                        </button>
                        {open && (
                          <ul id={`breakdown-${sl.id}`} aria-label={`Aufteilung ${sl.name}`} className="ml-1 mt-2 space-y-2 border-l-2 border-line pl-4">
                            {sl.children.map((sub) => (
                              <li key={sub.id} className="flex items-center gap-3 text-[13px] text-ink-2">
                                <span className="min-w-0 flex-1 truncate">{sub.name}</span>
                                <span className="text-ink-3">{share(sub.cents)}</span>
                                <span className="num w-20 text-right font-medium">{fmtShort(sub.cents)}</span>
                              </li>
                            ))}
                          </ul>
                        )}
                      </li>
                    )
                  })}
                </ul>
              </>
            )}
          </Tile>

          {/* People */}
          {multiplePeople && model.people.length > 0 && (
            <Tile className="lg:col-span-2">
              <TileLabel>Ausgaben nach Person</TileLabel>
              <ul className="mt-3 space-y-3.5">
                {model.people.map((p) => (
                  <li key={p.id}>
                    <div className="mb-1.5 flex items-center gap-2.5 text-[14px]">
                      <span className="grid size-7 place-items-center rounded-full bg-accent-soft text-[12px] font-semibold text-accent">{p.name.slice(0, 1)}</span>
                      <span className="flex-1 font-medium">{p.name}</span>
                      <span className="num font-semibold">{fmtShort(p.cents)}</span>
                    </div>
                    <Progress ratio={s.expenseCents ? p.cents / s.expenseCents : 0} level="ok" />
                  </li>
                ))}
              </ul>
            </Tile>
          )}

          {/* Budgets */}
          {model.budgets.length > 0 ? (
            <Tile className={cn(multiplePeople && model.people.length > 0 ? 'lg:col-span-2' : 'lg:col-span-4')}>
              <div className="flex items-center justify-between">
                <TileLabel>{model.warnings.length > 0 ? 'Budgets im Blick' : 'Budgets'}</TileLabel>
                <Link to="/budgets" className="text-[13px] font-medium text-accent">
                  Alle
                </Link>
              </div>
              <ul className="mt-3 space-y-4">
                {model.budgets.slice(0, 3).map((w) => {
                  const c = data.categories.get(w.categoryId)
                  return (
                    <li key={w.categoryId}>
                      <div className="mb-1.5 flex items-center gap-2.5 text-[14px]">
                        <CategoryIcon icon={c?.icon ?? ''} color={c?.color ?? '#999'} size="sm" />
                        <span className="min-w-0 flex-1 truncate font-medium">{c?.name}</span>
                        <span className={cn('num font-semibold', w.level === 'exceeded' ? 'text-neg' : w.level === 'warning' ? 'text-warn' : 'text-ink-3')}>
                          {Math.round(w.ratio * 100)} %
                        </span>
                      </div>
                      <Progress ratio={w.ratio} level={w.level} />
                    </li>
                  )
                })}
              </ul>
            </Tile>
          ) : (
            <Tile className={cn('flex items-center gap-4 bg-accent-soft shadow-none', multiplePeople && model.people.length > 0 ? 'lg:col-span-2' : 'lg:col-span-4')}>
              <PiggyBank className="size-8 shrink-0 text-accent" />
              <div className="text-[14px]">
                <div className="font-semibold">Budgets setzen</div>
                <Link to="/budgets" className="text-accent">
                  Monatslimits pro Kategorie festlegen
                </Link>
              </div>
            </Tile>
          )}

          {/* Trend (desktop and tablet) */}
          <Tile className="hidden md:col-span-2 md:block lg:col-span-4">
            <div className="flex items-center justify-between">
              <TileLabel>Letzte 12 Monate</TileLabel>
              <div className="flex gap-3 text-[12px] text-ink-3">
                <span className="flex items-center gap-1.5"><span className="size-2 rounded-full bg-pos" /> Einnahmen</span>
                <span className="flex items-center gap-1.5"><span className="size-2 rounded-full bg-ink" /> Ausgaben</span>
              </div>
            </div>
            <div className="mt-3 h-56">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={trend.map((t) => ({ ...t, label: monthShort(t.month) }))} barGap={3} margin={{ top: 8, right: 0, bottom: 0, left: 0 }}>
                  <XAxis dataKey="label" axisLine={false} tickLine={false} tick={{ fill: 'var(--ink-3)', fontSize: 12 }} />
                  <Tooltip cursor={{ fill: 'var(--tile-2)', radius: 12 }} content={<TrendTip />} />
                  <Bar dataKey="incomeCents" name="Einnahmen" fill="var(--pos)" radius={[6, 6, 6, 6]} maxBarSize={14} />
                  <Bar dataKey="expenseCents" name="Ausgaben" radius={[6, 6, 6, 6]} maxBarSize={14}>
                    {trend.map((t) => (
                      <Cell key={t.month} fill={t.month === month ? 'var(--accent)' : 'var(--ink)'} />
                    ))}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            </div>
          </Tile>

          {/* Recent */}
          <Tile className="md:col-span-2 lg:col-span-2">
            <div className="flex items-center justify-between">
              <TileLabel>Zuletzt</TileLabel>
              <Link to={`/buchungen${month !== monthOf(today()) ? `?monat=${month}` : ''}`} className="text-[13px] font-medium text-accent">
                Alle
              </Link>
            </div>
            {model.recent.length === 0 ? (
              <p className="py-8 text-center text-[14px] text-ink-3">Keine Buchungen in diesem Monat.</p>
            ) : (
              <div className="-mx-2 mt-2">
                {model.recent.map((t) => (
                  <TransactionRow key={t.id} tx={t} category={data.categories.get(t.categoryId)} label={tree.byId.has(t.categoryId) ? tree.labelFor(t.categoryId) : undefined} payerName={data.names.get(t.paidBy)} showPayer={multiplePeople} onClick={() => openEdit(t)} />
                ))}
              </div>
            )}
          </Tile>

          {/* Category trend (desktop and tablet) */}
          {catTrend.top.length > 0 && (
            <Tile className="hidden md:col-span-2 md:block lg:col-span-6">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <TileLabel>Kategorien im Verlauf · 6 Monate</TileLabel>
                <div className="flex flex-wrap gap-3 text-[12px] text-ink-3">
                  {catTrend.top.map((id) => (
                    <span key={id} className="flex items-center gap-1.5">
                      <span className="size-2 rounded-full" style={{ backgroundColor: data.categories.get(id)?.color ?? OTHERS_COLOR }} />
                      {data.categories.get(id)?.name ?? 'Unbekannt'}
                    </span>
                  ))}
                  <span className="flex items-center gap-1.5">
                    <span className="size-2 rounded-full" style={{ backgroundColor: OTHERS_COLOR }} /> Weitere
                  </span>
                </div>
              </div>
              <div className="mt-3 h-64">
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={catTrend.rows.map((r) => ({ ...r, label: monthShort(r.month) }))} margin={{ top: 8, right: 0, bottom: 0, left: 0 }}>
                    <XAxis dataKey="label" axisLine={false} tickLine={false} tick={{ fill: 'var(--ink-3)', fontSize: 12 }} />
                    <Tooltip cursor={{ fill: 'var(--tile-2)', radius: 12 }} content={<StackTip names={(id) => (id === 'others' ? 'Weitere' : data.categories.get(id)?.name ?? 'Unbekannt')} />} />
                    {[...catTrend.top, 'others'].map((id, i, all) => (
                      <Bar
                        key={id}
                        dataKey={id}
                        stackId="c"
                        fill={id === 'others' ? OTHERS_COLOR : data.categories.get(id)?.color ?? OTHERS_COLOR}
                        radius={i === all.length - 1 ? [8, 8, 0, 0] : [0, 0, 0, 0]}
                        maxBarSize={56}
                      />
                    ))}
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </Tile>
          )}

        </div>
      )}
    </>
  )
}

type TipProps = { active?: boolean; payload?: Array<{ name?: string; value?: number; payload?: Record<string, unknown> }> }

function ChartTip({ active, payload }: TipProps) {
  if (!active || !payload?.length) return null
  const p = payload[0]!
  return (
    <div className="rounded-xl bg-ink px-3 py-2 text-[13px] text-on-ink shadow-float">
      <div className="font-medium">{p.name}</div>
      <div className="num">{formatMoney(Number(p.value))}</div>
    </div>
  )
}

function TrendTip({ active, payload }: TipProps) {
  if (!active || !payload?.length) return null
  const row = payload[0]!.payload as { month: string; incomeCents: number; expenseCents: number }
  return (
    <div className="rounded-xl bg-ink px-3 py-2 text-[13px] text-on-ink shadow-float">
      <div className="mb-1 font-medium">{monthShort(row.month)} {row.month.slice(0, 4)}</div>
      <div className="num">+ {formatMoney(row.incomeCents)}</div>
      <div className="num">− {formatMoney(row.expenseCents)}</div>
    </div>
  )
}

function StackTip({ active, payload, names }: TipProps & { names(id: string): string }) {
  if (!active || !payload?.length) return null
  const row = payload[0]!.payload as { month: string }
  const parts = payload.filter((p) => Number(p.value) > 0).reverse()
  return (
    <div className="rounded-xl bg-ink px-3 py-2 text-[13px] text-on-ink shadow-float">
      <div className="mb-1 font-medium">
        {monthShort(row.month)} {row.month.slice(0, 4)}
      </div>
      {parts.map((p) => (
        <div key={String(p.name)} className="flex justify-between gap-4">
          <span>{names(String(p.name))}</span>
          <span className="num">{formatMoney(Number(p.value))}</span>
        </div>
      ))}
    </div>
  )
}

function OverviewSkeleton() {
  return (
    <div aria-busy="true" aria-label="Lädt">
      <Skeleton className="mb-6 mt-4 h-10 w-64" />
      <div className="grid gap-4 lg:grid-cols-6">
        <Skeleton className="h-52 rounded-tile lg:col-span-4" />
        <Skeleton className="h-52 rounded-tile lg:col-span-2" />
        <Skeleton className="h-40 rounded-tile lg:col-span-3" />
        <Skeleton className="h-40 rounded-tile lg:col-span-3" />
      </div>
    </div>
  )
}
