import { and, eq, ne, sql } from 'drizzle-orm'
import type { FastifyInstance } from 'fastify'
import type { ZodTypeProvider } from 'fastify-type-provider-zod'
import { z } from 'zod'
import { hashPassword, verifyPassword } from '../auth/passwords.js'
import { hashRefreshToken } from '../auth/tokens.js'
import type { Db } from '../db/client.js'
import { LOCK_SYNC, LOCK_USERS, lock } from '../db/locks.js'
import { refreshTokens, users } from '../db/schema.js'
import { AppError } from '../errors.js'
import { displayNameSchema, passwordSchema, setupBody, toUserDto, userDto } from './dto.js'

const patchMeBody = z.object({
  displayName: displayNameSchema.optional(),
  currentPassword: z.string().max(1024).optional(),
  newPassword: passwordSchema.optional().describe('Requires a correct currentPassword.'),
  keepRefreshToken: z
    .string()
    .max(256)
    .optional()
    .describe(
      'When changing the password, all of the user\'s refresh tokens are revoked except this one (if it belongs to the user). Omit to revoke all.',
    ),
})

const createUserBody = setupBody.extend({ isAdmin: z.boolean().optional() })

const patchUserBody = z.object({
  displayName: displayNameSchema.optional(),
  password: passwordSchema.optional().describe('Admin password reset; revokes all refresh tokens of the user.'),
  isAdmin: z.boolean().optional(),
})

const idParams = z.object({ id: z.string().uuid() })

const bump = () => ({ version: sql`nextval('sync_version_seq')`, updatedAt: sql`now()` })

function isUniqueViolation(e: unknown): boolean {
  const err = e as { code?: string; cause?: { code?: string } }
  return err?.code === '23505' || err?.cause?.code === '23505'
}

async function revokeAllRefreshTokens(db: Db, userId: string, keepToken?: string): Promise<void> {
  const where = keepToken
    ? and(eq(refreshTokens.userId, userId), ne(refreshTokens.tokenHash, hashRefreshToken(keepToken)))
    : eq(refreshTokens.userId, userId)
  await db.delete(refreshTokens).where(where)
}

export async function userRoutes(app: FastifyInstance): Promise<void> {
  const r = app.withTypeProvider<ZodTypeProvider>()

  r.get('/me', { onRequest: app.authenticate, schema: { response: { 200: userDto } } }, async (req) => {
    const [row] = await app.db.select().from(users).where(eq(users.id, req.user.id))
    if (!row || row.deleted) throw new AppError(401, 'unauthorized', 'User no longer exists')
    return toUserDto(row)
  })

  r.patch(
    '/me',
    { onRequest: app.authenticate, schema: { body: patchMeBody, response: { 200: userDto } } },
    async (req) => {
      const { displayName, currentPassword, newPassword, keepRefreshToken } = req.body
      const [row] = await app.db.select().from(users).where(eq(users.id, req.user.id))
      if (!row || row.deleted) throw new AppError(401, 'unauthorized', 'User no longer exists')

      const changes: { displayName?: string; passwordHash?: string } = {}
      if (displayName !== undefined) changes.displayName = displayName
      if (newPassword !== undefined) {
        if (!currentPassword || !(await verifyPassword(row.passwordHash, currentPassword))) {
          throw new AppError(400, 'wrong_password', 'Current password is incorrect')
        }
        changes.passwordHash = await hashPassword(newPassword)
      }
      if (Object.keys(changes).length === 0) return toUserDto(row)

      const updated = await app.db.transaction(async (tx) => {
        await lock(tx, LOCK_SYNC)
        const [u] = await tx
          .update(users)
          .set({ ...changes, ...bump() })
          .where(eq(users.id, row.id))
          .returning()
        if (changes.passwordHash) await revokeAllRefreshTokens(tx as unknown as Db, row.id, keepRefreshToken)
        return u!
      })
      return toUserDto(updated)
    },
  )

  r.get(
    '/users',
    { onRequest: [app.authenticate, app.requireAdmin], schema: { response: { 200: z.array(userDto) } } },
    async () => {
      const rows = await app.db.select().from(users).where(eq(users.deleted, false)).orderBy(users.createdAt)
      return rows.map(toUserDto)
    },
  )

  r.post(
    '/users',
    {
      onRequest: [app.authenticate, app.requireAdmin],
      schema: { body: createUserBody, response: { 201: userDto } },
    },
    async (req, reply) => {
      const { username, displayName, password, isAdmin } = req.body
      const passwordHash = await hashPassword(password)
      try {
        const created = await app.db.transaction(async (tx) => {
          await lock(tx, LOCK_SYNC)
          const [row] = await tx
            .insert(users)
            .values({ username, displayName, passwordHash, isAdmin: isAdmin ?? false })
            .returning()
          return row
        })
        return reply.status(201).send(toUserDto(created!))
      } catch (e) {
        if (isUniqueViolation(e)) throw new AppError(409, 'username_taken', 'Username is already taken')
        throw e
      }
    },
  )

  r.patch(
    '/users/:id',
    {
      onRequest: [app.authenticate, app.requireAdmin],
      schema: { params: idParams, body: patchUserBody, response: { 200: userDto } },
    },
    async (req) => {
      const { displayName, password, isAdmin } = req.body
      const passwordHash = password !== undefined ? await hashPassword(password) : undefined

      const updated = await app.db.transaction(async (tx) => {
        // Serialize admin changes so two concurrent demotions cannot remove the last admin.
        await lock(tx, LOCK_USERS)
        await lock(tx, LOCK_SYNC)
        const [target] = await tx.select().from(users).where(eq(users.id, req.params.id))
        if (!target || target.deleted) throw new AppError(404, 'user_not_found', 'User not found')

        if (isAdmin === false && target.isAdmin) {
          const others = await tx
            .select({ id: users.id })
            .from(users)
            .where(and(eq(users.isAdmin, true), eq(users.deleted, false), ne(users.id, target.id)))
            .limit(1)
          if (others.length === 0) throw new AppError(409, 'last_admin', 'Cannot remove the last admin')
        }

        const changes: Partial<typeof users.$inferInsert> = {}
        if (displayName !== undefined) changes.displayName = displayName
        if (passwordHash !== undefined) changes.passwordHash = passwordHash
        if (isAdmin !== undefined) changes.isAdmin = isAdmin
        if (Object.keys(changes).length === 0) return target

        const [u] = await tx
          .update(users)
          .set({ ...changes, ...bump() })
          .where(eq(users.id, target.id))
          .returning()
        if (passwordHash !== undefined) await revokeAllRefreshTokens(tx as unknown as Db, target.id)
        return u!
      })
      return toUserDto(updated)
    },
  )
}
