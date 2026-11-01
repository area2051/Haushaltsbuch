import { PostgreSqlContainer, type StartedPostgreSqlContainer } from '@testcontainers/postgresql'
import type { TestProject } from 'vitest/node'
import { createDb, runMigrations } from '../src/db/client.js'

let container: StartedPostgreSqlContainer | undefined

export async function setup(project: TestProject) {
  container = await new PostgreSqlContainer('postgres:17').start()
  const url = container.getConnectionUri()
  const { db, close } = createDb(url)
  try {
    await runMigrations(db)
  } finally {
    await close()
  }
  project.provide('databaseUrl', url)
}

export async function teardown() {
  await container?.stop()
}

declare module 'vitest' {
  export interface ProvidedContext {
    databaseUrl: string
  }
}
