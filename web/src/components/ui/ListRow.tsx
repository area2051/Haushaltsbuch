import { ChevronRight, type LucideIcon } from 'lucide-react'
import type { ReactNode } from 'react'
import { Link } from 'react-router'
import { cn } from '../../lib/cn'

/** Row inside a tile group; a link when `to` is set. */
export function ListRow({ icon: Icon, tint, label, detail, to, onClick, trailing }: { icon?: LucideIcon; tint?: string; label: ReactNode; detail?: ReactNode; to?: string; onClick?(): void; trailing?: ReactNode }) {
  const body = (
    <>
      {Icon && (
        <span className={cn('grid size-9 shrink-0 place-items-center rounded-xl', tint ?? 'bg-tile-2 text-ink-2')}>
          <Icon className="size-[18px]" />
        </span>
      )}
      <span className="min-w-0 flex-1">
        <span className="block truncate text-[15px] font-medium">{label}</span>
        {detail && <span className="block truncate text-[13px] text-ink-3">{detail}</span>}
      </span>
      {trailing ?? ((to || onClick) && <ChevronRight className="size-5 shrink-0 text-ink-3" />)}
    </>
  )
  const cls = 'flex w-full items-center gap-3 rounded-2xl px-3 py-2.5 text-left transition hover:bg-tile-2'
  if (to) return <Link to={to} className={cls}>{body}</Link>
  if (onClick) return <button type="button" onClick={onClick} className={cls}>{body}</button>
  return <div className={cls}>{body}</div>
}

export function Group({ title, children }: { title?: string; children: ReactNode }) {
  return (
    <section className="space-y-1.5">
      {title && <h2 className="px-3 text-[13px] font-semibold text-ink-3">{title}</h2>}
      <div className="rounded-tile bg-tile p-1.5 shadow-tile">{children}</div>
    </section>
  )
}
