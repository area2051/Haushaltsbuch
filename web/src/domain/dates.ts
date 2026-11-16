/** Calendar day `YYYY-MM-DD` without time zone. Strings compare correctly with `<` / `>`. */
export type Day = string
/** Month `YYYY-MM`. */
export type Month = string

const pad = (n: number, w = 2) => String(n).padStart(w, '0')

function parts(d: Day): [number, number, number] {
  return d.split('-').map(Number) as [number, number, number]
}

const fromUtc = (dt: Date): Day =>
  `${pad(dt.getUTCFullYear(), 4)}-${pad(dt.getUTCMonth() + 1)}-${pad(dt.getUTCDate())}`

/** Noon UTC of the day, safe for Intl formatting with `timeZone: 'UTC'`. */
const noonUtc = (d: Day) => {
  const [y, m, dd] = parts(d)
  return new Date(Date.UTC(y, m - 1, dd, 12))
}

export function isValidDay(s: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return false
  const [y, m, d] = parts(s)
  return y >= 1 && fromUtc(new Date(Date.UTC(y, m - 1, d))) === s
}

/** Today in the browser's time zone. */
export function today(now: Date = new Date()): Day {
  return `${pad(now.getFullYear(), 4)}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`
}

export function addDays(d: Day, days: number): Day {
  const [y, m, dd] = parts(d)
  return fromUtc(new Date(Date.UTC(y, m - 1, dd + days)))
}

export const monthOf = (d: Day): Month => d.slice(0, 7)

export function addMonths(m: Month, n: number): Month {
  const [y, mm] = m.split('-').map(Number) as [number, number]
  const index = y * 12 + (mm - 1) + n
  const year = Math.floor(index / 12)
  return `${pad(year, 4)}-${pad(index - year * 12 + 1)}`
}

export function daysInMonth(m: Month): number {
  const [y, mm] = m.split('-').map(Number) as [number, number]
  return new Date(Date.UTC(y, mm, 0)).getUTCDate()
}

export const firstDay = (m: Month): Day => `${m}-01`
export const lastDay = (m: Month): Day => `${m}-${pad(daysInMonth(m))}`

/** „November 2026“ */
export const monthTitle = (m: Month): string =>
  new Intl.DateTimeFormat('de-DE', { month: 'long', year: 'numeric', timeZone: 'UTC' }).format(noonUtc(firstDay(m)))

/** „01.02.2026“ */
export function germanDate(d: Day): string {
  const [y, m, dd] = parts(d)
  return `${pad(dd)}.${pad(m)}.${pad(y, 4)}`
}

/** „Heute“, „Gestern“, „Montag, 2. November“ (with year when not the current one). */
export function dayHeading(d: Day, now: Day = today()): string {
  if (d === now) return 'Heute'
  if (d === addDays(now, -1)) return 'Gestern'
  const opts: Intl.DateTimeFormatOptions = { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC' }
  if (d.slice(0, 4) !== now.slice(0, 4)) opts.year = 'numeric'
  return new Intl.DateTimeFormat('de-DE', opts).format(noonUtc(d))
}

/** „Nov“, „Mär“ (chart axes) */
export const monthShort = (m: Month): string =>
  new Intl.DateTimeFormat('de-DE', { month: 'short', timeZone: 'UTC' }).format(noonUtc(firstDay(m))).replace('.', '')
