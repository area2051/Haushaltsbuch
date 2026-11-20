import { type Day, germanDate } from './dates'
import type { CategoryTree } from './categoryTree'
import type { Transaction } from './types'

const HEADER = 'Datum;Art;Kategorie;Unterkategorie;Betrag;Notiz;Bezahlt von'

/** 123456 → „1234,56“ (no grouping, no currency sign). */
const amount = (cents: number): string => `${Math.floor(cents / 100)},${String(cents % 100).padStart(2, '0')}`

const escape = (s: string): string => (/[;"\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s)

/** CSV for Excel (DE): `;`-separated, decimal comma, CRLF, sorted by date (stable). */
export function makeCsv(
  txs: Transaction[],
  tree: CategoryTree,
  members: Map<string, string>,
  from: Day,
  to: Day,
): string {
  // Array.prototype.sort is stable, so same-day rows keep their input order.
  const rows = txs.filter((t) => t.date >= from && t.date <= to).sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0))
  let out = HEADER + '\r\n'
  for (const t of rows) {
    const root = tree.byId.get(tree.rootOf(t.categoryId))
    const own = tree.byId.get(t.categoryId)
    const fields = [
      germanDate(t.date),
      t.kind === 'income' ? 'Einnahme' : 'Ausgabe',
      root?.name ?? '',
      own && own !== root ? own.name : '',
      amount(t.amountCents),
      t.note ?? '',
      members.get(t.paidBy) ?? '',
    ]
    out += fields.map(escape).join(';') + '\r\n'
  }
  return out
}

/** UTF-8 with BOM so Excel detects the encoding. */
export const csvBlob = (csv: string): Blob => new Blob(['﻿', csv], { type: 'text/csv;charset=utf-8' })

export const csvFileName = (from: Day, to: Day): string => `Haushaltsbuch_${from}_${to}.csv`
