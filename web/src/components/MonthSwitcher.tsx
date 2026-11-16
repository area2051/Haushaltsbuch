import { ChevronLeft, ChevronRight } from 'lucide-react'
import { useEffect } from 'react'
import { addMonths, type Month, monthTitle } from '../domain/dates'

export function MonthSwitcher({ month, onChange, max }: { month: Month; onChange(m: Month): void; max?: Month }) {
  const canNext = !max || month < max
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLElement && e.target.closest('input, textarea, select, [role=dialog]')) return
      if (e.key === 'ArrowLeft') onChange(addMonths(month, -1))
      if (e.key === 'ArrowRight' && canNext) onChange(addMonths(month, 1))
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [month, onChange, canNext])

  return (
    <div className="inline-flex items-center gap-1 rounded-full bg-tile p-1 shadow-tile">
      <button aria-label="Vorheriger Monat" onClick={() => onChange(addMonths(month, -1))} className="grid size-9 place-items-center rounded-full text-ink-2 hover:bg-tile-2">
        <ChevronLeft className="size-5" />
      </button>
      <span className="min-w-[8.5rem] text-center text-[15px] font-semibold tracking-tight" aria-live="polite">
        {monthTitle(month)}
      </span>
      <button
        aria-label="Nächster Monat"
        disabled={!canNext}
        onClick={() => onChange(addMonths(month, 1))}
        className="grid size-9 place-items-center rounded-full text-ink-2 hover:bg-tile-2 disabled:opacity-30"
      >
        <ChevronRight className="size-5" />
      </button>
    </div>
  )
}
