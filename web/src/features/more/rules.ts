import { isValidDay } from '../../domain/dates'
import type { Frequency, Kind, RecurringRuleInput } from '../../domain/types'

export type RuleDraft = {
  cents: number
  kind: Kind
  categoryId: string
  paidBy: string
  note: string
  frequency: Frequency
  startDate: string
  /** '' = no end */
  endDate: string
}

export type RuleProblem = 'amount' | 'category' | 'paidBy' | 'startDate' | 'endDate' | 'note'

/** Mirrors the server's rule validation (start ≥ 2000-01-01, end ≥ start). */
export function ruleProblem(d: RuleDraft): RuleProblem | null {
  if (d.cents <= 0) return 'amount'
  if (!d.categoryId) return 'category'
  if (!d.paidBy) return 'paidBy'
  if (!isValidDay(d.startDate) || d.startDate < '2000-01-01') return 'startDate'
  if (d.endDate && (!isValidDay(d.endDate) || d.endDate < d.startDate)) return 'endDate'
  if (d.note.trim().length > 200) return 'note'
  return null
}

export function toRule(d: RuleDraft, id: string): RecurringRuleInput {
  const note = d.note.trim()
  return {
    id,
    amountCents: d.cents,
    kind: d.kind,
    categoryId: d.categoryId,
    paidBy: d.paidBy,
    note: note || null,
    frequency: d.frequency,
    startDate: d.startDate,
    endDate: d.endDate || null,
    deleted: false,
  }
}

const utcNoon = (day: string) => new Date(`${day}T12:00:00Z`)

/** „Wöchentlich am Montag“, „Monatlich am 3.“, „Jährlich am 3. November“ (from the start date). */
export function ruleSchedule(f: Frequency, startDate: string): string {
  const day = Number(startDate.slice(8, 10))
  if (f === 'weekly') return `Wöchentlich am ${new Intl.DateTimeFormat('de-DE', { weekday: 'long', timeZone: 'UTC' }).format(utcNoon(startDate))}`
  if (f === 'monthly') return day > 28 ? `Monatlich am ${day}. (sonst Monatsletzter)` : `Monatlich am ${day}.`
  return `Jährlich am ${new Intl.DateTimeFormat('de-DE', { day: 'numeric', month: 'long', timeZone: 'UTC' }).format(utcNoon(startDate))}`
}
