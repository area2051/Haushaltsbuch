import Fastify, { type FastifyInstance } from 'fastify'
import { serializerCompiler, validatorCompiler } from 'fastify-type-provider-zod'
import { registerAuth } from './auth/plugin.js'
import { authRoutes } from './auth/routes.js'
import type { Clock } from './clock.js'
import { systemClock, todayIn } from './clock.js'
import type { Config } from './config.js'
import type { Db } from './db/client.js'
import { errorHandler, notFoundHandler } from './errors.js'
import { generateDueTransactions } from './recurring/generator.js'
import { setupRoutes } from './setup/routes.js'
import { syncRoutes } from './sync/routes.js'
import { userRoutes } from './users/routes.js'

export type AppDeps = {
  config: Config
  db: Db
  clock?: Clock
  /** Runs after a sync that changed recurring rules. Defaults to generating due transactions. */
  onRulesChanged?: () => Promise<void>
}

export async function buildApp(deps: AppDeps): Promise<FastifyInstance> {
  const { clock = systemClock } = deps
  const app = Fastify({ logger: process.env.NODE_ENV === 'test' ? false : true })

  app.setValidatorCompiler(validatorCompiler)
  app.setSerializerCompiler(serializerCompiler)
  app.setErrorHandler(errorHandler)
  app.setNotFoundHandler(notFoundHandler)

  app.decorate('config', deps.config)
  app.decorate('clock', clock)
  app.decorate('db', deps.db)

  registerAuth(app)

  await app.register(setupRoutes)
  await app.register(authRoutes)
  await app.register(userRoutes)
  await app.register(syncRoutes, {
    onRulesChanged:
      deps.onRulesChanged ??
      (() => generateDueTransactions(deps.db, todayIn(clock, deps.config.timeZone)).then(() => {})),
  })

  return app
}

declare module 'fastify' {
  interface FastifyInstance {
    config: Config
    clock: Clock
    db: Db
  }
}
