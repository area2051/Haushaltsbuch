import Fastify, { type FastifyInstance } from 'fastify'
import { serializerCompiler, validatorCompiler } from 'fastify-type-provider-zod'
import type { Clock } from './clock.js'
import { systemClock } from './clock.js'
import type { Config } from './config.js'
import { errorHandler, notFoundHandler } from './errors.js'

export type AppDeps = {
  config: Config
  /** Typed and required from Task 2 on. */
  db?: unknown
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

  return app
}

declare module 'fastify' {
  interface FastifyInstance {
    config: Config
    clock: Clock
  }
}
