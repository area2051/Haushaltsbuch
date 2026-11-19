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

/** Months per step for monthly/yearly rules (`interval` = every N units). */
const stepMonths = (frequency: Frequency, interval: number) => (frequency === 'monthly' ? 1 : 12) * interval

/** The k-th occurrence (k = 0 is startDate), always anchored at startDate. */
function occurrence(startDate: string, frequency: Frequency, k: number, interval: number): string {
  const { y, m, d } = parse(startDate)
  if (frequency === 'weekly') {
    const t = new Date((dayNumber(startDate) + 7 * interval * k) * DAY_MS)
    return format(t.getUTCFullYear(), t.getUTCMonth() + 1, t.getUTCDate())
  }
  const months = stepMonths(frequency, interval) * k
  const idx = y * 12 + (m - 1) + months
  const ty = Math.floor(idx / 12)
  const tm = (idx % 12) + 1
  return format(ty, tm, Math.min(d, daysInMonth(ty, tm)))
}

/** Smallest k >= 0 whose occurrence is >= date (ISO strings compare lexicographically). */
function indexOnOrAfter(startDate: string, frequency: Frequency, date: string, interval: number): number {
  if (startDate >= date) return 0
  let k: number
  if (frequency === 'weekly') {
    k = Math.floor((dayNumber(date) - dayNumber(startDate)) / (7 * interval))
  } else {
    const a = parse(startDate)
    const b = parse(date)
    const months = (b.y - a.y) * 12 + (b.m - a.m)
    k = Math.floor(months / stepMonths(frequency, interval))
  }
  k = Math.max(0, k - 1)
  while (occurrence(startDate, frequency, k, interval) < date) k++
  return k
}

/** First occurrence (anchored at startDate) that is >= date; startDate if startDate >= date. */
export function firstOccurrenceOnOrAfter(startDate: string, frequency: Frequency, date: string, interval = 1): string {
  return occurrence(startDate, frequency, indexOnOrAfter(startDate, frequency, date, interval), interval)
}

/** Next occurrence strictly after `after`, anchored at startDate. `interval` = every N weeks/months/years. */
export function nextOccurrence(startDate: string, frequency: Frequency, after: string, interval = 1): string {
  let k = indexOnOrAfter(startDate, frequency, after, interval)
  while (occurrence(startDate, frequency, k, interval) <= after) k++
  return occurrence(startDate, frequency, k, interval)
}

export function dueDates(
  rule: { startDate: string; frequency: Frequency; interval?: number; nextDueDate: string; endDate: string | null },
  today: string,
): { dates: string[]; nextDueDate: string } {
  const dates: string[] = []
  let next = rule.nextDueDate
  while (next <= today && (rule.endDate === null || next <= rule.endDate)) {
    dates.push(next)
    next = nextOccurrence(rule.startDate, rule.frequency, next, rule.interval ?? 1)
  }
  return { dates, nextDueDate: next }
}
