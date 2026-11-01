import { count, sql } from 'drizzle-orm'
import type { FastifyInstance } from 'fastify'
import type { ZodTypeProvider } from 'fastify-type-provider-zod'
import { z } from 'zod'
import { hashPassword } from '../auth/passwords.js'
import { categories, users } from '../db/schema.js'
import { AppError } from '../errors.js'
import { toUserDto, userDto } from '../users/dto.js'
import { DEFAULT_CATEGORIES } from './defaultCategories.js'

const setupBody = z.object({
  username: z.string().min(3).max(32).regex(/^[a-z0-9._-]+$/),
  displayName: z.string().min(1).max(50),
  password: z.string().min(8),
})

export async function setupRoutes(app: FastifyInstance): Promise<void> {
  const r = app.withTypeProvider<ZodTypeProvider>()

  r.get(
    '/health',
    { schema: { response: { 200: z.object({ status: z.literal('ok'), setupRequired: z.boolean() }) } } },
    async () => {
      const [row] = await app.db.select({ n: count() }).from(users)
      return { status: 'ok' as const, setupRequired: (row?.n ?? 0) === 0 }
    },
  )

  r.post(
    '/setup',
    { schema: { body: setupBody, response: { 201: z.object({ user: userDto }) } } },
    async (req, reply) => {
      const { username, displayName, password } = req.body
      const passwordHash = await hashPassword(password)
      const user = await app.db.transaction(async (tx) => {
        await tx.execute(sql`SELECT pg_advisory_xact_lock(1)`)
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
