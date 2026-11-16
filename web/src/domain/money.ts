import type { Kind } from './types'

const MAX_CENTS = 999_999_999
const eur = new Intl.NumberFormat('de-DE', { style: 'currency', currency: 'EUR' })

/** „1.234,56 €“ */
export const formatMoney = (cents: number): string => eur.format(cents / 100)

/** Einnahme „+12,50 €“, Ausgabe „−12,50 €“ (U+2212). */
export const formatSigned = (cents: number, kind: Kind): string =>
  (kind === 'income' ? '+' : '−') + formatMoney(cents)

/**
 * Parses a typed amount into cents: „12,5“, „1.234,56“, „12.50“, „1.234“.
 * A comma is the decimal separator; dots are grouping unless they are the only separator
 * followed by 1–2 digits. Returns null for invalid input or amounts ≤ 0 or above the limit.
 */
export function parseMoney(input: string): number | null {
  let s = input.replace(/[\s€]/g, '')
  if (s.includes(',')) s = s.replace(/\./g, '').replace(',', '.')
  else if (/^\d{1,3}(\.\d{3})+$/.test(s)) s = s.replace(/\./g, '')
  if (!/^\d+(\.\d{1,2})?$/.test(s)) return null
  const [whole, frac = ''] = s.split('.') as [string, string?]
  const cents = Number(whole) * 100 + Number(frac.padEnd(2, '0'))
  return cents > 0 && cents <= MAX_CENTS ? cents : null
}

/** cents → „12,50“ for edit fields. */
export const centsToInput = (cents: number): string =>
  `${Math.floor(cents / 100)},${String(cents % 100).padStart(2, '0')}`
