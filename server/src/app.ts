import Fastify, { type FastifyInstance } from 'fastify'
import { serializerCompiler, validatorCompiler } from 'fastify-type-provider-zod'
import type { Clock } from './clock.js'
import { systemClock } from './clock.js'
import type { Config } from './config.js'
import type { Db } from './db/client.js'
import { errorHandler, notFoundHandler } from './errors.js'
import { setupRoutes } from './setup/routes.js'

export type AppDeps = {
  config: Config
  db: Db
  clock?: Clock
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

  await app.register(setupRoutes)

  return app
}

declare module 'fastify' {
  interface FastifyInstance {
    config: Config
    clock: Clock
    db: Db
  }
}
