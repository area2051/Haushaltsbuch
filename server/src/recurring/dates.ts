export type Frequency = 'weekly' | 'monthly' | 'yearly'

const DAY_MS = 86_400_000

function parse(s: string): { y: number; m: number; d: number } {
  const [y, m, d] = s.split('-').map(Number) as [number, number, number]
  return { y, m, d }
}

function format(y: number, m: number, d: number): string {
  return `${String(y).padStart(4, '0')}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`
}

function daysInMonth(y: number, m: number): number {
  return new Date(Date.UTC(y, m, 0)).getUTCDate()
}

function dayNumber(s: string): number {
  const { y, m, d } = parse(s)
  return Math.round(Date.UTC(y, m - 1, d) / DAY_MS)
}

/** The k-th occurrence (k = 0 is startDate), always anchored at startDate. */
function occurrence(startDate: string, frequency: Frequency, k: number): string {
  const { y, m, d } = parse(startDate)
  if (frequency === 'weekly') {
    const t = new Date((dayNumber(startDate) + 7 * k) * DAY_MS)
    return format(t.getUTCFullYear(), t.getUTCMonth() + 1, t.getUTCDate())
  }
  const months = frequency === 'monthly' ? k : 12 * k
  const idx = y * 12 + (m - 1) + months
  const ty = Math.floor(idx / 12)
  const tm = (idx % 12) + 1
  return format(ty, tm, Math.min(d, daysInMonth(ty, tm)))
}

/** Smallest k >= 0 whose occurrence is >= date (ISO strings compare lexicographically). */
function indexOnOrAfter(startDate: string, frequency: Frequency, date: string): number {
  if (startDate >= date) return 0
  let k: number
  if (frequency === 'weekly') {
    k = Math.floor((dayNumber(date) - dayNumber(startDate)) / 7)
  } else {
    const a = parse(startDate)
    const b = parse(date)
    const months = (b.y - a.y) * 12 + (b.m - a.m)
    k = Math.floor(frequency === 'monthly' ? months : months / 12)
  }
  k = Math.max(0, k - 1)
  while (occurrence(startDate, frequency, k) < date) k++
  return k
}

/** First occurrence (anchored at startDate) that is >= date; startDate if startDate >= date. */
export function firstOccurrenceOnOrAfter(startDate: string, frequency: Frequency, date: string): string {
  return occurrence(startDate, frequency, indexOnOrAfter(startDate, frequency, date))
}

/** Next occurrence strictly after `after`, anchored at startDate. */
export function nextOccurrence(startDate: string, frequency: Frequency, after: string): string {
  let k = indexOnOrAfter(startDate, frequency, after)
  while (occurrence(startDate, frequency, k) <= after) k++
  return occurrence(startDate, frequency, k)
}

export function dueDates(
  rule: { startDate: string; frequency: Frequency; nextDueDate: string; endDate: string | null },
  today: string,
): { dates: string[]; nextDueDate: string } {
  const dates: string[] = []
  let next = rule.nextDueDate
  while (next <= today && (rule.endDate === null || next <= rule.endDate)) {
    dates.push(next)
    next = nextOccurrence(rule.startDate, rule.frequency, next)
  }
  return { dates, nextDueDate: next }
}
