import { Command } from 'cmdk'
import { CalendarClock, CircleEllipsis, Download, LayoutGrid, ListOrdered, type LucideIcon, Plus, Search, Shapes, Target, User } from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router'
import { useData } from '../../app/AppContext'
import { CategoryIcon } from '../../components/CategoryIcon'
import { categoryTree } from '../../domain/categoryTree'
import { germanDate } from '../../domain/dates'
import { formatSigned } from '../../domain/money'
import { useEntry } from '../quickEntry/EntrySheet'
import { emptyFilter, sections } from '../transactions/list'

type Action = { label: string; icon: LucideIcon; hint?: string; run(): void }

const fold = (s: string) => s.normalize('NFD').replace(/\p{M}/gu, '').toLocaleLowerCase('de')

/** ⌘K / Ctrl+K: jump to pages, start an entry, find transactions. */
export function CommandPalette() {
  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState('')
  const navigate = useNavigate()
  const { openNew, openEdit } = useEntry()
  const data = useData()

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault()
        setOpen((o) => !o)
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  const close = () => {
    setOpen(false)
    setQuery('')
  }
  const go = (to: string) => () => navigate(to)

  const actions: Action[] = [
    { label: 'Neue Buchung', icon: Plus, hint: 'N', run: openNew },
    { label: 'Übersicht', icon: LayoutGrid, run: go('/') },
    { label: 'Buchungen', icon: ListOrdered, run: go('/buchungen') },
    { label: 'Budgets', icon: Target, run: go('/budgets') },
    { label: 'Kategorien', icon: Shapes, run: go('/mehr/kategorien') },
    { label: 'Wiederkehrende Buchungen', icon: CalendarClock, run: go('/mehr/wiederkehrend') },
    { label: 'CSV-Export', icon: Download, run: go('/mehr/export') },
    { label: 'Profil und Passwort', icon: User, run: go('/mehr/profil') },
    { label: 'Mehr', icon: CircleEllipsis, run: go('/mehr') },
  ]
  const q = fold(query.trim())
  const shownActions = q ? actions.filter((a) => fold(a.label).includes(q)) : actions
  const matches = useMemo(
    () =>
      q.length < 2
        ? []
        : sections([...data.transactions.values()], { ...emptyFilter, search: query }, categoryTree([...data.categories.values()]))
            .flatMap((s) => s.items)
            .slice(0, 8),
    [q, query, data.transactions, data.categories],
  )

  const item = 'flex cursor-pointer items-center gap-3 rounded-2xl px-3 py-2.5 text-[15px] data-[selected=true]:bg-tile-2'

  return (
    <Command.Dialog
      open={open}
      onOpenChange={(o) => (o ? setOpen(true) : close())}
      label="Befehle und Suche"
      shouldFilter={false}
      overlayClassName="fixed inset-0 z-40 bg-black/30 backdrop-blur-[2px]"
      contentClassName="fixed left-1/2 top-[12vh] z-50 w-[min(600px,calc(100vw-24px))] -translate-x-1/2 overflow-hidden rounded-[24px] bg-bg shadow-float outline-none"
    >
      <div className="flex items-center gap-3 border-b border-line px-5">
        <Search className="size-5 shrink-0 text-ink-3" />
        <Command.Input value={query} onValueChange={setQuery} placeholder="Suchen oder springen …" className="h-14 w-full bg-transparent text-[16px] outline-none placeholder:text-ink-3" />
      </div>
      <Command.List className="max-h-[60vh] overflow-y-auto p-2">
        <Command.Empty className="px-3 py-8 text-center text-[14px] text-ink-3">Nichts gefunden.</Command.Empty>
        {shownActions.length > 0 && (
          <Command.Group heading="Aktionen" className="[&_[cmdk-group-heading]]:px-3 [&_[cmdk-group-heading]]:py-2 [&_[cmdk-group-heading]]:text-[12px] [&_[cmdk-group-heading]]:font-semibold [&_[cmdk-group-heading]]:text-ink-3">
            {shownActions.map((a) => (
              <Command.Item key={a.label} value={a.label} onSelect={() => (close(), a.run())} className={item}>
                <a.icon className="size-[18px] text-ink-2" />
                <span className="flex-1">{a.label}</span>
                {a.hint && <kbd className="rounded-md bg-tile-2 px-1.5 text-[12px] text-ink-3">{a.hint}</kbd>}
              </Command.Item>
            ))}
          </Command.Group>
        )}
        {matches.length > 0 && (
          <Command.Group heading="Buchungen" className="[&_[cmdk-group-heading]]:px-3 [&_[cmdk-group-heading]]:py-2 [&_[cmdk-group-heading]]:text-[12px] [&_[cmdk-group-heading]]:font-semibold [&_[cmdk-group-heading]]:text-ink-3">
            {matches.map((t) => {
              const c = data.categories.get(t.categoryId)
              return (
                <Command.Item key={t.id} value={t.id} onSelect={() => (close(), openEdit(t))} className={item}>
                  <CategoryIcon icon={c?.icon ?? ''} color={c?.color ?? '#999'} size="sm" />
                  <span className="min-w-0 flex-1">
                    <span className="block truncate">{t.note || c?.name}</span>
                    <span className="block text-[12px] text-ink-3">
                      {c?.name} · {germanDate(t.date)}
                    </span>
                  </span>
                  <span className="num text-[14px] font-semibold">{formatSigned(t.amountCents, t.kind)}</span>
                </Command.Item>
              )
            })}
          </Command.Group>
        )}
      </Command.List>
    </Command.Dialog>
  )
}
