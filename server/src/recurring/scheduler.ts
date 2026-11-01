import { Cron } from 'croner'
import { type Clock, todayIn } from '../clock.js'
import { pruneExpiredRefreshTokens } from '../auth/tokens.js'
import type { Db } from '../db/client.js'
import { generateDueTransactions } from './generator.js'

export type SchedulerLogger = { error(obj: unknown, msg: string): void }

/**
 * Daily at 03:00 (in `timeZone`) and once right away (catch-up after downtime): generates due
 * transactions and deletes expired refresh tokens. Errors are logged, never thrown; a failure of
 * one job does not skip the other.
 */
export function startScheduler(
  db: Db,
  clock: Clock,
  timeZone: string,
  logger: SchedulerLogger = { error: (obj, msg) => console.error(msg, obj) },
): { stop(): void } {
  const tick = async (): Promise<void> => {
    try {
      await generateDueTransactions(db, todayIn(clock, timeZone))
    } catch (err) {
      logger.error({ err }, 'recurring transaction generation failed')
    }
    try {
      await pruneExpiredRefreshTokens(db, clock.now())
    } catch (err) {
      logger.error({ err }, 'pruning expired refresh tokens failed')
    }
  }
  const job = new Cron('0 3 * * *', { timezone: timeZone }, tick)
  void tick()
  return { stop: () => job.stop() }
}
