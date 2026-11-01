import type { Clock } from '../clock.js'
import { AppError } from '../errors.js'

const MAX_FAILURES = 5
const WINDOW_MS = 60_000
const LOCK_MS = 60_000

type Entry = { failures: number; windowStart: number; lockedUntil: number }

export type LoginLimiter = {
  /** Throws AppError 429 `too_many_attempts` while the username is locked. */
  check(username: string): void
  fail(username: string): void
  reset(username: string): void
}

/**
 * In-memory failed-login counter per username: 5 failures within 60 s lock the
 * username for 60 s. Unknown usernames are counted as well.
 */
export function createLoginLimiter(clock: Clock): LoginLimiter {
  const entries = new Map<string, Entry>()

  function prune(now: number): void {
    for (const [key, e] of entries) {
      if (e.lockedUntil <= now && now - e.windowStart >= WINDOW_MS) entries.delete(key)
    }
  }

  return {
    check(username) {
      const e = entries.get(username)
      if (e && e.lockedUntil > clock.now().getTime()) {
        throw new AppError(429, 'too_many_attempts', 'Too many failed login attempts, try again later')
      }
    },
    fail(username) {
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
      entries.delete(username)
    },
  }
}
