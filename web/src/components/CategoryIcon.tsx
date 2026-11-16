import { iconFor } from '../domain/icons'
import { cn } from '../lib/cn'

const sizes = { sm: 'size-9 rounded-xl [&>svg]:size-[18px]', md: 'size-11 rounded-2xl [&>svg]:size-5', lg: 'size-14 rounded-[20px] [&>svg]:size-6' }

/** Category symbol on a soft tint of the category color. */
export function CategoryIcon({ icon, color, size = 'md', className }: { icon: string; color: string; size?: keyof typeof sizes; className?: string }) {
  const Icon = iconFor(icon)
  return (
    <span
      aria-hidden
      className={cn('grid shrink-0 place-items-center', sizes[size], className)}
      style={{ backgroundColor: `color-mix(in oklab, ${color} 16%, var(--tile))`, color: `color-mix(in oklab, ${color} 80%, var(--ink))` }}
    >
      <Icon strokeWidth={2} />
    </span>
  )
}
