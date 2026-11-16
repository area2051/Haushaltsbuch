import { Repeat } from 'lucide-react'
import type { Category, Transaction } from '../domain/types'
import { formatSigned } from '../domain/money'
import { cn } from '../lib/cn'
import { CategoryIcon } from './CategoryIcon'

export function TransactionRow({
  tx,
  category,
  payerName,
  showPayer,
  onClick,
}: {
  tx: Transaction
  category?: Category
  payerName?: string
  showPayer?: boolean
  onClick?(): void
}) {
  const subtitle = [tx.note, showPayer ? payerName : null].filter(Boolean).join(' · ')
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex w-full items-center gap-3 rounded-2xl px-2 py-2.5 text-left transition hover:bg-tile-2 active:scale-[0.99]"
    >
      <CategoryIcon icon={category?.icon ?? ''} color={category?.color ?? '#8A8276'} />
      <span className="min-w-0 flex-1">
        <span className="flex items-center gap-1.5 truncate text-[15px] font-medium">
          {category?.name ?? 'Ohne Kategorie'}
          {tx.recurringRuleId && <Repeat aria-label="wiederkehrend" className="size-3.5 shrink-0 text-ink-3" />}
        </span>
        {subtitle && <span className="block truncate text-[13px] text-ink-3">{subtitle}</span>}
      </span>
      <span className={cn('num shrink-0 text-[15px] font-semibold', tx.kind === 'income' ? 'text-pos' : 'text-ink')}>
        {formatSigned(tx.amountCents, tx.kind)}
      </span>
    </button>
  )
}
