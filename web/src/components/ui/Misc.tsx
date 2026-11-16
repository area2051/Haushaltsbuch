import { ChevronLeft } from 'lucide-react'
import { Link } from 'react-router'
import { animate, useMotionValue, useTransform, motion } from 'motion/react'
import type { LucideIcon } from 'lucide-react'
import { type ReactNode, useEffect } from 'react'
import { cn } from '../../lib/cn'

export function Skeleton({ className }: { className?: string }) {
  return <div className={cn('animate-pulse rounded-2xl bg-tile-2', className)} />
}

export function EmptyState({ icon: Icon, title, text, action }: { icon: LucideIcon; title: string; text: string; action?: ReactNode }) {
  return (
    <div className="flex flex-col items-center px-6 py-14 text-center">
      <div className="mb-4 grid size-16 place-items-center rounded-[22px] bg-accent-soft text-accent">
        <Icon className="size-7" strokeWidth={1.75} />
      </div>
      <h3 className="text-lg font-semibold tracking-tight">{title}</h3>
      <p className="mt-1 max-w-xs text-[15px] text-ink-3">{text}</p>
      {action && <div className="mt-5">{action}</div>}
    </div>
  )
}

export function PageHeader({ title, subtitle, actions }: { title: string; subtitle?: ReactNode; actions?: ReactNode }) {
  return (
    <header className="mb-5 flex flex-col gap-3 px-1 pt-3 sm:flex-row sm:items-end sm:justify-between lg:mb-7 lg:pt-4">
      <div className="min-w-0">
        {subtitle && <div className="mb-0.5 text-[13px] font-medium text-ink-3">{subtitle}</div>}
        <h1 className="text-balance text-[28px] font-semibold leading-tight tracking-[-0.03em] lg:text-[34px]">{title}</h1>
      </div>
      {actions && <div className="flex shrink-0 flex-wrap items-center gap-2">{actions}</div>}
    </header>
  )
}

/** Progress bar; level colors match budget levels. */
export function Progress({ ratio, level, className }: { ratio: number; level: 'ok' | 'warning' | 'exceeded'; className?: string }) {
  const width = `${Math.min(Math.max(ratio, 0), 1) * 100}%`
  const color = level === 'exceeded' ? 'bg-neg' : level === 'warning' ? 'bg-warn' : 'bg-ink'
  return (
    <div className={cn('h-2 overflow-hidden rounded-full bg-tile-2', className)}>
      <motion.div className={cn('h-full rounded-full', color)} initial={{ width: 0 }} animate={{ width }} transition={{ type: 'spring', stiffness: 120, damping: 20 }} />
    </div>
  )
}

/** Number that counts to its new value. */
export function AnimatedNumber({ value, format }: { value: number; format(v: number): string }) {
  const mv = useMotionValue(value)
  const text = useTransform(mv, (v) => format(Math.round(v)))
  useEffect(() => {
    const controls = animate(mv, value, { duration: 0.6, ease: [0.22, 1, 0.36, 1] })
    return () => controls.stop()
  }, [mv, value])
  return <motion.span>{text}</motion.span>
}

export function BackLink({ to = '/mehr', label = 'Mehr' }: { to?: string; label?: string }) {
  return (
    <Link to={to} className="inline-flex items-center gap-1 text-[13px] font-medium text-accent">
      <ChevronLeft className="size-4" /> {label}
    </Link>
  )
}
