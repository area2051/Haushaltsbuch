import { isValidDay } from '../../domain/dates'
import type { Kind, TransactionInput } from '../../domain/types'

/** Form state of the entry/edit sheet. */
export type Draft = { cents: number; kind: Kind; categoryId: string; date: string; paidBy: string; note: string }

export type DraftProblem = 'amount' | 'category' | 'date' | 'paidBy' | 'note'

const NOTE_MAX = 200

/** First field that keeps the draft from being saved, or null. */
export function draftProblem(d: Draft): DraftProblem | null {
  if (d.cents <= 0) return 'amount'
  if (!d.categoryId) return 'category'
  if (!isValidDay(d.date)) return 'date'
  if (!d.paidBy) return 'paidBy'
  if (d.note.trim().length > NOTE_MAX) return 'note'
  return null
}

export function toTransaction(d: Draft, id: string, recurringRuleId: string | null = null): TransactionInput {
  const note = d.note.trim()
  return {
    id,
    amountCents: d.cents,
    kind: d.kind,
    categoryId: d.categoryId,
    date: d.date,
    paidBy: d.paidBy,
    note: note === '' ? null : note,
    recurringRuleId,
    deleted: false,
  }
}
