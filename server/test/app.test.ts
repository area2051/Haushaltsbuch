import { expect, test } from 'vitest'
import { z } from 'zod'
import type { ZodTypeProvider } from 'fastify-type-provider-zod'
import { buildApp } from '../src/app.js'
import { AppError } from '../src/errors.js'
import type { Config } from '../src/config.js'

const config: Config = {
  databaseUrl: 'postgres://x',
  jwtSecret: 'x'.repeat(32),
  port: 3000,
  timeZone: 'Europe/Berlin',
}

test('unknown route returns error envelope', async () => {
  const app = await buildApp({ config })
  const res = await app.inject({ method: 'GET', url: '/nope' })
  expect(res.statusCode).toBe(404)
  expect(res.json()).toEqual({ error: { code: 'not_found', message: expect.any(String) } })
})

test('AppError is rendered with its code', async () => {
  const app = await buildApp({ config })
  app.get('/boom', async () => {
    throw new AppError(409, 'conflict', 'x')
  })
  const res = await app.inject({ method: 'GET', url: '/boom' })
  expect(res.statusCode).toBe(409)
  expect(res.json()).toEqual({ error: { code: 'conflict', message: 'x' } })
})

test('unexpected error returns 500 without internals', async () => {
  const app = await buildApp({ config })
  app.get('/boom', async () => {
    throw new Error('secret')
  })
  const res = await app.inject({ method: 'GET', url: '/boom' })
  expect(res.statusCode).toBe(500)
  expect(res.json().error.code).toBe('internal')
  expect(res.body).not.toContain('secret')
})

test('validation error returns 400 validation_failed', async () => {
  const app = await buildApp({ config })
  app.withTypeProvider<ZodTypeProvider>().post(
    '/echo',
    { schema: { body: z.object({ name: z.string() }) } },
    async (req) => ({ name: req.body.name }),
  )
  const bad = await app.inject({ method: 'POST', url: '/echo', payload: { name: 5 } })
  expect(bad.statusCode).toBe(400)
  expect(bad.json().error.code).toBe('validation_failed')
  const ok = await app.inject({ method: 'POST', url: '/echo', payload: { name: 'a' } })
  expect(ok.statusCode).toBe(200)
  expect(ok.json()).toEqual({ name: 'a' })
})
