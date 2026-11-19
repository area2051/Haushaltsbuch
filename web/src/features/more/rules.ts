import { isValidDay } from '../../domain/dates'
import type { Frequency, Kind, RecurringRuleInput } from '../../domain/types'

export type RuleDraft = {
  cents: number
  kind: Kind
  categoryId: string
  paidBy: string
  note: string
  frequency: Frequency
  /** Every N units (1–24). */
  interval: number
  startDate: string
  /** '' = no end */
  endDate: string
}

export type RuleProblem = 'amount' | 'category' | 'paidBy' | 'interval' | 'startDate' | 'endDate' | 'note'

/** Mirrors the server's rule validation (start ≥ 2000-01-01, end ≥ start). */
export function ruleProblem(d: RuleDraft): RuleProblem | null {
  if (d.cents <= 0) return 'amount'
  if (!d.categoryId) return 'category'
  if (!d.paidBy) return 'paidBy'
  if (!Number.isInteger(d.interval) || d.interval < 1 || d.interval > MAX_INTERVAL) return 'interval'
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
    interval: d.interval,
    startDate: d.startDate,
    endDate: d.endDate || null,
    deleted: false,
  }
}

export const MAX_INTERVAL = 24

export type PresetId = 'weekly' | 'biweekly' | 'monthly' | 'quarterly' | 'halfyearly' | 'yearly'
export type RhythmPreset = { id: PresetId; label: string; frequency: Frequency; interval: number }

/** Rhythms offered in the select box; anything else is „Alle N …“ (custom). Same list as iOS. */
export const RHYTHM_PRESETS: RhythmPreset[] = [
  { id: 'weekly', label: 'Wöchentlich', frequency: 'weekly', interval: 1 },
  { id: 'biweekly', label: 'Alle 2 Wochen', frequency: 'weekly', interval: 2 },
  { id: 'monthly', label: 'Monatlich', frequency: 'monthly', interval: 1 },
  { id: 'quarterly', label: 'Vierteljährlich', frequency: 'monthly', interval: 3 },
  { id: 'halfyearly', label: 'Halbjährlich', frequency: 'monthly', interval: 6 },
  { id: 'yearly', label: 'Jährlich', frequency: 'yearly', interval: 1 },
]

export const presetFor = (f: Frequency, interval: number): PresetId | 'custom' =>
  RHYTHM_PRESETS.find((p) => p.frequency === f && p.interval === interval)?.id ?? 'custom'

const UNIT_PLURAL: Record<Frequency, string> = { weekly: 'Wochen', monthly: 'Monate', yearly: 'Jahre' }

/** „Monatlich“, „Vierteljährlich“, „Alle 4 Monate“ … */
export function rhythmLabel(f: Frequency, interval: number): string {
  const preset = RHYTHM_PRESETS.find((p) => p.frequency === f && p.interval === interval)
  return preset?.label ?? `Alle ${interval} ${UNIT_PLURAL[f]}`
}

const utcNoon = (day: string) => new Date(`${day}T12:00:00Z`)

/** „Wöchentlich am Montag“, „Vierteljährlich am 15.“, „Alle 2 Jahre am 3. November“ (from the start date). */
export function ruleSchedule(f: Frequency, interval: number, startDate: string): string {
  const rhythm = rhythmLabel(f, interval)
  const day = Number(startDate.slice(8, 10))
  if (f === 'weekly') return `${rhythm} am ${new Intl.DateTimeFormat('de-DE', { weekday: 'long', timeZone: 'UTC' }).format(utcNoon(startDate))}`
  if (f === 'monthly') return day > 28 ? `${rhythm} am ${day}. (sonst Monatsletzter)` : `${rhythm} am ${day}.`
  return `${rhythm} am ${new Intl.DateTimeFormat('de-DE', { day: 'numeric', month: 'long', timeZone: 'UTC' }).format(utcNoon(startDate))}`
}
