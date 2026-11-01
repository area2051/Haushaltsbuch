import { fileURLToPath } from 'node:url'
import { drizzle, type PostgresJsDatabase } from 'drizzle-orm/postgres-js'
import { migrate } from 'drizzle-orm/postgres-js/migrator'
import postgres from 'postgres'
import * as schema from './schema.js'

export type Db = PostgresJsDatabase<typeof schema>

export function createDb(url: string): { db: Db; close(): Promise<void> } {
  const client = postgres(url, { onnotice: () => {} })
  const db = drizzle(client, { schema })
  return { db, close: () => client.end() }
}

const migrationsFolder = fileURLToPath(new URL('../../drizzle', import.meta.url))

export async function runMigrations(db: Db): Promise<void> {
  await migrate(db, { migrationsFolder })
}
