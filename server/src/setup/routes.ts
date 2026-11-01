import { count } from 'drizzle-orm'
import type { FastifyInstance } from 'fastify'
import type { ZodTypeProvider } from 'fastify-type-provider-zod'
import { z } from 'zod'
import { hashPassword } from '../auth/passwords.js'
import { LOCK_SETUP, LOCK_SYNC, lock } from '../db/locks.js'
import { categories, users } from '../db/schema.js'
import { AppError, errorResponses } from '../errors.js'
import { setupBody, toUserDto, userDto } from '../users/dto.js'
import { DEFAULT_CATEGORIES } from './defaultCategories.js'

export async function setupRoutes(app: FastifyInstance): Promise<void> {
  const r = app.withTypeProvider<ZodTypeProvider>()

  r.get(
    '/health',
    {
      schema: {
        operationId: 'getHealth',
        security: [],
        response: {
          200: z.object({ status: z.literal('ok'), setupRequired: z.boolean() }).meta({ id: 'HealthResponse' }),
          ...errorResponses(),
        },
      },
    },
    async () => {
      const [row] = await app.db.select({ n: count() }).from(users)
      return { status: 'ok' as const, setupRequired: (row?.n ?? 0) === 0 }
    },
  )

  r.post(
    '/setup',
    {
      schema: {
        operationId: 'setup',
        security: [],
        body: setupBody,
        response: {
          201: z.object({ user: userDto }).meta({ id: 'SetupResponse' }),
          ...errorResponses(400, 409),
        },
      },
    },
    async (req, reply) => {
      const { username, displayName, password } = req.body
      const passwordHash = await hashPassword(password)
      const user = await app.db.transaction(async (tx) => {
        await lock(tx, LOCK_SETUP)
        await lock(tx, LOCK_SYNC)
        const [row] = await tx.select({ n: count() }).from(users)
        if ((row?.n ?? 0) > 0) {
          throw new AppError(409, 'setup_already_done', 'Setup has already been completed')
        }
        const [created] = await tx
          .insert(users)
          .values({ username, displayName, passwordHash, isAdmin: true })
          .returning()
        await tx
          .insert(categories)
          .values(DEFAULT_CATEGORIES.map((c, i) => ({ ...c, sortOrder: i })))
        return created!
      })
      return reply.status(201).send({
        user: toUserDto(user),
      })
    },
  )
}
