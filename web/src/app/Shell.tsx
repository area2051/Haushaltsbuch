import { CircleEllipsis, LayoutGrid, ListOrdered, Plus, Target, WifiOff } from 'lucide-react'
import { AnimatePresence, motion } from 'motion/react'
import { NavLink, Outlet, useLocation } from 'react-router'
import { useApp, useData } from './AppContext'
import { CommandPalette } from '../features/palette/CommandPalette'
import { EntryProvider, useEntry } from '../features/quickEntry/EntrySheet'
import { cn } from '../lib/cn'

const NAV = [
  { to: '/', label: 'Übersicht', icon: LayoutGrid, end: true },
  { to: '/buchungen', label: 'Buchungen', icon: ListOrdered },
  { to: '/budgets', label: 'Budgets', icon: Target },
  { to: '/mehr', label: 'Mehr', icon: CircleEllipsis },
]

function OfflineBanner() {
  const { online } = useData()
  const { store } = useApp()
  return (
    <AnimatePresence>
      {!online && (
        <motion.div
          initial={{ opacity: 0, y: -8 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: -8 }}
          role="status"
          className="mb-4 flex items-center gap-2 rounded-2xl bg-warn-soft px-4 py-3 text-[14px] font-medium text-warn"
        >
          <WifiOff className="size-4 shrink-0" />
          <span className="flex-1">Keine Verbindung zur NAS – Änderungen sind gerade nicht möglich.</span>
          <button onClick={() => void store.pull().catch(() => {})} className="shrink-0 rounded-full bg-warn px-3 py-1 text-[13px] font-semibold text-bg">
            Erneut verbinden
          </button>
        </motion.div>
      )}
    </AnimatePresence>
  )
}

function Sidebar() {
  const { openNew } = useEntry()
  const { user } = useApp()
  return (
    <aside className="sticky top-0 hidden h-dvh w-64 shrink-0 flex-col p-4 lg:flex">
      <div className="flex h-full flex-col rounded-[28px] bg-tile/70 p-4 shadow-tile backdrop-blur-xl">
        <div className="mb-8 flex items-center gap-3 px-2 pt-2">
          <img src="/app/icon.svg" alt="" className="size-9 rounded-xl" />
          <div className="leading-tight">
            <div className="text-[15px] font-semibold tracking-tight">Haushaltsbuch</div>
            <div className="text-[12px] text-ink-3">{user?.displayName}</div>
          </div>
        </div>
        <Button onClick={openNew} />
        <nav className="mt-6 space-y-1" aria-label="Hauptnavigation">
          {NAV.map(({ to, label, icon: Icon, end }) => (
            <NavLink
              key={to}
              to={to}
              end={end}
              className={({ isActive }) =>
                cn('flex h-11 items-center gap-3 rounded-full px-4 text-[15px] font-medium transition', isActive ? 'bg-ink text-on-ink' : 'text-ink-2 hover:bg-tile-2')
              }
            >
              <Icon className="size-[18px]" /> {label}
            </NavLink>
          ))}
        </nav>
        <div className="mt-auto space-y-1.5 px-2 text-[12px] text-ink-3">
          <p>
            <kbd className="rounded-md bg-tile-2 px-1.5 py-0.5 font-sans">N</kbd> neue Buchung
          </p>
          <p>
            <kbd className="rounded-md bg-tile-2 px-1.5 py-0.5 font-sans">{/Mac|iPhone|iPad/.test(navigator.platform) ? '⌘' : 'Strg'} K</kbd> suchen und springen
          </p>
        </div>
      </div>
    </aside>
  )
}

function Button({ onClick }: { onClick(): void }) {
  return (
    <button onClick={onClick} className="flex h-12 w-full items-center justify-center gap-2 rounded-full bg-ink text-[15px] font-semibold text-on-ink shadow-tile transition hover:opacity-90 active:scale-[0.98]">
      <Plus className="size-5" strokeWidth={2.5} /> Neue Buchung
    </button>
  )
}

function TabBar() {
  const { openNew } = useEntry()
  const tab = (i: number) => {
    const { to, label, icon: Icon, end } = NAV[i]!
    return (
      <NavLink key={to} to={to} end={end} className={({ isActive }) => cn('flex flex-1 flex-col items-center gap-0.5 py-1.5 text-[11px] font-medium transition', isActive ? 'text-ink' : 'text-ink-3')}>
        {({ isActive }) => (
          <>
            <Icon className="size-[22px]" strokeWidth={isActive ? 2.4 : 1.9} />
            {label}
          </>
        )}
      </NavLink>
    )
  }
  return (
    <nav aria-label="Hauptnavigation" className="fixed inset-x-0 bottom-0 z-30 px-3 pb-[max(env(safe-area-inset-bottom),12px)] lg:hidden">
      <div className="mx-auto flex max-w-md items-center rounded-[26px] bg-tile/85 px-2 py-1.5 shadow-float backdrop-blur-xl">
        {tab(0)}
        {tab(1)}
        <button
          onClick={openNew}
          aria-label="Neue Buchung"
          className="mx-1 grid size-14 shrink-0 place-items-center rounded-[20px] bg-ink text-on-ink shadow-tile transition active:scale-95"
        >
          <Plus className="size-7" strokeWidth={2.5} />
        </button>
        {tab(2)}
        {tab(3)}
      </div>
    </nav>
  )
}

export function Shell() {
  const location = useLocation()
  return (
    <EntryProvider>
      <div className="mx-auto flex min-h-dvh max-w-[1440px]">
        <Sidebar />
        <main className="min-w-0 flex-1 px-4 pb-32 pt-safe sm:px-6 lg:px-8 lg:pb-12 lg:pt-4">
          <OfflineBanner />
          <motion.div key={location.pathname} initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.25, ease: [0.22, 1, 0.36, 1] }}>
            <Outlet />
          </motion.div>
        </main>
      </div>
      <TabBar />
      <CommandPalette />
    </EntryProvider>
  )
}
