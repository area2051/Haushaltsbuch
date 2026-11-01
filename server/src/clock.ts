export interface Clock {
  now(): Date
}

export const systemClock: Clock = { now: () => new Date() }

/** Calendar date (YYYY-MM-DD) of the clock's current instant in the given time zone. */
export function todayIn(clock: Clock, timeZone: string): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(clock.now())
}
