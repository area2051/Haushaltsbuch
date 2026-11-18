import { type Day, type Month, monthOf } from '../../domain/dates'
import type { Category, Kind, Transaction } from '../../domain/types'

export type TxFilter = {
  search: string
  categoryId: string | null
  paidBy: string | null
  kind: Kind | null
  month: Month | null
}

export const emptyFilter: TxFilter = { search: '', categoryId: null, paidBy: null, kind: null, month: null }

/** True when a chip filter (kind, category, payer) is set. */
export const filterActive = (f: TxFilter): boolean => f.kind !== null || f.categoryId !== null || f.paidBy !== null

export type DaySection = { day: Day; items: Transaction[]; netCents: number }

const fold = (s: string) => s.normalize('NFD').replace(/\p{M}/gu, '').toLocaleLowerCase('de')

/** Filtered transactions grouped by day: newest day first, newest entry (version) first within a day. */
export function sections(txs: Transaction[], f: TxFilter, categories: Map<string, Category>): DaySection[] {
  const query = fold(f.search.trim())
  const groups = new Map<Day, Transaction[]>()
  for (const t of txs) {
    if (f.kind && t.kind !== f.kind) continue
    if (f.categoryId && t.categoryId !== f.categoryId) continue
    if (f.paidBy && t.paidBy !== f.paidBy) continue
    if (f.month && monthOf(t.date) !== f.month) continue
    if (query && ![t.note ?? '', categories.get(t.categoryId)?.name ?? ''].some((field) => fold(field).includes(query))) continue
    const list = groups.get(t.date)
    if (list) list.push(t)
    else groups.set(t.date, [t])
  }
  return [...groups]
    .sort(([a], [b]) => (a < b ? 1 : -1))
    .map(([day, items]) => ({
      day,
      items: items.sort((a, b) => b.version - a.version),
      netCents: items.reduce((sum, t) => sum + (t.kind === 'income' ? t.amountCents : -t.amountCents), 0),
    }))
}
