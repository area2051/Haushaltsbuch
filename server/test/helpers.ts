import { sql } from 'drizzle-orm'
import type { FastifyInstance } from 'fastify'
import { inject } from 'vitest'
import { buildApp } from '../src/app.js'
import type { Clock } from '../src/clock.js'
import type { Config } from '../src/config.js'
import { createDb, type Db } from '../src/db/client.js'

export class MutableClock implements Clock {
  private current: Date
  constructor(iso: string) {
    this.current = new Date(iso)
  }
  now(): Date {
    return new Date(this.current)
  }
  set(iso: string): void {
    this.current = new Date(iso)
  }
  advance(ms: number): void {
    this.current = new Date(this.current.getTime() + ms)
  }
}

export async function createTestApp(opts: { now?: string } = {}): Promise<{
  app: FastifyInstance
  db: Db
  clock: MutableClock
  close(): Promise<void>
}> {
  const databaseUrl = inject('databaseUrl')
  const { db, close: closeDb } = createDb(databaseUrl)
  try {
    await db.execute(
      sql`TRUNCATE users, refresh_tokens, categories, transactions, budgets, recurring_rules RESTART IDENTITY CASCADE`,
    )
    await db.execute(sql`ALTER SEQUENCE sync_version_seq RESTART`)
    const clock = new MutableClock(opts.now ?? '2026-01-15T12:00:00Z')
    const config: Config = {
      databaseUrl,
      jwtSecret: 'test-secret-test-secret-test-secret-123',
      port: 3000,
      timeZone: 'Europe/Berlin',
    }
    const app = await buildApp({ config, db, clock })
    return {
      app,
      db,
      clock,
      close: async () => {
        await app.close()
        await closeDb()
      },
    }
  } catch (e) {
    await closeDb()
    throw e
  }
}

export type UserDto = { id: string; username: string; displayName: string; isAdmin: boolean }

export async function setupAdmin(
  app: FastifyInstance,
  overrides: Partial<{ username: string; displayName: string; password: string }> = {},
): Promise<UserDto> {
  const res = await app.inject({
    method: 'POST',
    url: '/setup',
    payload: { username: 'admin', displayName: 'Admin', password: 'geheim123', ...overrides },
  })
  if (res.statusCode !== 201) throw new Error(`setup failed: ${res.statusCode} ${res.body}`)
  return res.json().user as UserDto
}
