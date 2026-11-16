import type { HTMLAttributes } from 'react'
import { cn } from '../../lib/cn'

/** The bento tile: white (or tinted) surface with a large radius. */
export function Tile({ className, ...rest }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn('rounded-tile bg-tile p-5 shadow-tile', className)} {...rest} />
}

export function TileLabel({ className, ...rest }: HTMLAttributes<HTMLParagraphElement>) {
  return <p className={cn('text-[13px] font-medium text-ink-3', className)} {...rest} />
}
