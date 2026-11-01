import type { Clock } from '../clock.js'
import { AppError } from '../errors.js'

const MAX_FAILURES = 5
const WINDOW_MS = 60_000
const LOCK_MS = 60_000

type Entry = { failures: number; windowStart: number; lockedUntil: number }

export type LoginLimiter = {
  /**
   * Throws AppError 429 `too_many_attempts` while the username is locked, or
   * when recorded failures plus attempts still in flight reach the limit.
   * Otherwise reserves one attempt, which must be settled with exactly one of
   * `fail`, `reset` or `release`.
   */
  check(username: string): void
  /** Settles the reservation as a failed attempt. */
  fail(username: string): void
  /** Settles the reservation as a success and clears all failures. */
  reset(username: string): void
  /** Settles the reservation without an outcome (e.g. unexpected error). */
  release(username: string): void
}

/**
 * In-memory failed-login counter per username: 5 failures within 60 s lock the
 * username for 60 s. Unknown usernames are counted as well. Attempts in flight
 * count against the limit so parallel requests cannot bypass it.
 */
export function createLoginLimiter(clock: Clock): LoginLimiter {
  const entries = new Map<string, Entry>()
  const pending = new Map<string, number>()

  function prune(now: number): void {
    for (const [key, e] of entries) {
      if (e.lockedUntil <= now && now - e.windowStart >= WINDOW_MS) entries.delete(key)
    }
  }

  function settle(username: string): void {
    const n = (pending.get(username) ?? 0) - 1
    if (n > 0) pending.set(username, n)
    else pending.delete(username)
  }

  function tooMany(): AppError {
    return new AppError(429, 'too_many_attempts', 'Too many failed login attempts, try again later')
  }

  return {
    check(username) {
      const now = clock.now().getTime()
      const e = entries.get(username)
      if (e && e.lockedUntil > now) throw tooMany()
      const failures = e && now - e.windowStart < WINDOW_MS ? e.failures : 0
      const inFlight = pending.get(username) ?? 0
      if (failures + inFlight >= MAX_FAILURES) throw tooMany()
      pending.set(username, inFlight + 1)
    },
    fail(username) {
      settle(username)
      const now = clock.now().getTime()
      if (entries.size > 10_000) prune(now)
      let e = entries.get(username)
      if (!e || now - e.windowStart >= WINDOW_MS) {
        e = { failures: 0, windowStart: now, lockedUntil: e?.lockedUntil ?? 0 }
        entries.set(username, e)
      }
      e.failures += 1
      if (e.failures >= MAX_FAILURES) {
        e.lockedUntil = now + LOCK_MS
        e.failures = 0
        e.windowStart = now
      }
    },
    reset(username) {
      settle(username)
      entries.delete(username)
    },
    release(username) {
      settle(username)
    },
  }
}
