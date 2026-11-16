/** Ziffernblock-Eingabe: Ziffern werden von rechts eingeschoben (1,2,5,0 → 12,50 €). Max. 9 Ziffern. */
const MAX_CENTS = 999_999_999

export function appendDigit(cents: number, digit: number): number {
  if (!Number.isInteger(digit) || digit < 0 || digit > 9) return cents
  const next = cents * 10 + digit
  return next <= MAX_CENTS ? next : cents
}

export const deleteLast = (cents: number): number => Math.floor(cents / 10)
