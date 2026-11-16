import { ChevronDown } from 'lucide-react'
import { cn } from '../../lib/cn'

/** Pill-shaped native select (best picker on phones). Filled when a value is set. */
export function ChipSelect({
  label,
  value,
  onChange,
  options,
}: {
  label: string
  value: string | null
  onChange(v: string | null): void
  options: Array<{ value: string; label: string }>
}) {
  const active = value !== null
  return (
    <label className={cn('relative inline-flex h-9 shrink-0 items-center rounded-full pl-3.5 pr-8 text-[14px] font-medium transition', active ? 'bg-ink text-on-ink' : 'bg-tile text-ink-2 shadow-tile')}>
      <span className="pointer-events-none">{active ? options.find((o) => o.value === value)?.label ?? label : label}</span>
      <ChevronDown className="pointer-events-none absolute right-2.5 size-4 opacity-70" />
      <select aria-label={label} value={value ?? ''} onChange={(e) => onChange(e.target.value || null)} className="absolute inset-0 cursor-pointer opacity-0">
        <option value="">{`${label}: alle`}</option>
        {options.map((o) => (
          <option key={o.value} value={o.value}>
            {o.label}
          </option>
        ))}
      </select>
    </label>
  )
}
