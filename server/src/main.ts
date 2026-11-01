import { loadConfig } from './config.js'
import { createDb, runMigrations } from './db/client.js'
import { buildApp } from './app.js'
import { startScheduler } from './recurring/scheduler.js'
import { systemClock } from './clock.js'

const config = loadConfig(process.env)
const { db, close } = createDb(config.databaseUrl)

await runMigrations(db)
const app = await buildApp({ config, db })
const scheduler = startScheduler(db, systemClock, config.timeZone, app.log)

let shuttingDown = false
async function shutdown(signal: string): Promise<void> {
  if (shuttingDown) return
  shuttingDown = true
  app.log.info({ signal }, 'shutting down')
  scheduler.stop()
  await app.close()
  await close()
  process.exit(0)
}
process.on('SIGTERM', () => void shutdown('SIGTERM'))
process.on('SIGINT', () => void shutdown('SIGINT'))

await app.listen({ host: '0.0.0.0', port: config.port })
