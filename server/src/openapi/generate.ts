import { writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { buildApp } from '../app.js'
import { createDb } from '../db/client.js'
import { serializeSpec } from './stableSpec.js'

/** Builds the app without touching a database (the connection is lazy) and writes `openapi.json`. */
async function main(): Promise<void> {
  const databaseUrl = 'postgres://openapi:openapi@localhost:5432/openapi'
  const { db, close } = createDb(databaseUrl)
  const app = await buildApp({
    config: { databaseUrl, jwtSecret: 'openapi-generation-only-openapi-generation', port: 3000, timeZone: 'UTC' },
    db,
  })
  try {
    await app.ready()
    const out = fileURLToPath(new URL('../../openapi.json', import.meta.url))
    writeFileSync(out, serializeSpec(app.swagger()))
    console.log(`wrote ${out}`)
  } finally {
    await app.close()
    await close()
  }
}

await main()
