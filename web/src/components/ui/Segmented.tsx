import { motion } from 'motion/react'
import { useId } from 'react'
import { cn } from '../../lib/cn'

type Option<T extends string> = { value: T; label: string }

export function Segmented<T extends string>({
  value,
  onChange,
  options,
  className,
  label,
}: {
  value: T
  onChange(v: T): void
  options: Option<T>[]
  className?: string
  label: string
}) {
  const id = useId()
  return (
    <div role="radiogroup" aria-label={label} className={cn('flex rounded-full bg-tile-2 p-1', className)}>
      {options.map((o) => {
        const active = o.value === value
        return (
          <button
            key={o.value}
            type="button"
            role="radio"
            aria-checked={active}
            onClick={() => onChange(o.value)}
            className={cn('relative h-9 flex-1 rounded-full px-4 text-sm font-medium transition-colors', active ? 'text-ink' : 'text-ink-3 hover:text-ink-2')}
          >
            {active && (
              <motion.span
                layoutId={`seg-${id}`}
                className="absolute inset-0 rounded-full bg-tile shadow-tile"
                transition={{ type: 'spring', stiffness: 500, damping: 38 }}
              />
            )}
            <span className="relative">{o.label}</span>
          </button>
        )
      })}
    </div>
  )
}
