import { and, eq, ne, sql } from 'drizzle-orm'
import type { FastifyInstance } from 'fastify'
import type { ZodTypeProvider } from 'fastify-type-provider-zod'
import { z } from 'zod'
import { hashPassword, verifyPassword } from '../auth/passwords.js'
import { hashRefreshToken } from '../auth/tokens.js'
import type { Db } from '../db/client.js'
import { LOCK_SYNC, LOCK_USERS, lock } from '../db/locks.js'
import { refreshTokens, users } from '../db/schema.js'
import { AppError, errorResponses } from '../errors.js'
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
}).meta({ id: 'UpdateMeRequest' })

const createUserBody = setupBody.extend({ isAdmin: z.boolean().optional() }).meta({ id: 'CreateUserRequest' })

const patchUserBody = z.object({
  displayName: displayNameSchema.optional(),
  password: passwordSchema.optional().describe('Admin password reset; revokes all refresh tokens of the user.'),
  isAdmin: z.boolean().optional(),
  deleted: z
    .boolean()
    .optional()
    .describe(
      'true removes the member: soft delete (synced as UserRecord.deleted), all refresh tokens revoked, login blocked. '
        + 'Fails with 409 cannot_delete_self for the calling admin and 409 last_admin for the last admin. '
        + 'false is ignored (no undelete); a deleted user yields 404.',
    ),
}).meta({ id: 'UpdateUserRequest' })

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

  r.get(
    '/me',
    {
      onRequest: app.authenticate,
      schema: {
        operationId: 'getMe',
        security: [{ bearerAuth: [] }],
        response: { 200: userDto, ...errorResponses(401) },
      },
    },
    async (req) => {
      const [row] = await app.db.select().from(users).where(eq(users.id, req.user.id))
      if (!row || row.deleted) throw new AppError(401, 'unauthorized', 'User no longer exists')
      return toUserDto(row)
    },
  )

  r.patch(
    '/me',
    {
      onRequest: app.authenticate,
      schema: {
        operationId: 'updateMe',
        security: [{ bearerAuth: [] }],
        body: patchMeBody,
        response: { 200: userDto, ...errorResponses(400, 401) },
      },
    },
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
    {
      onRequest: [app.authenticate, app.requireAdmin],
      schema: {
        operationId: 'listUsers',
        security: [{ bearerAuth: [] }],
        response: { 200: z.array(userDto), ...errorResponses(401, 403) },
      },
    },
    async () => {
      const rows = await app.db.select().from(users).where(eq(users.deleted, false)).orderBy(users.createdAt)
      return rows.map(toUserDto)
    },
  )

  r.post(
    '/users',
    {
      onRequest: [app.authenticate, app.requireAdmin],
      schema: {
        operationId: 'createUser',
        security: [{ bearerAuth: [] }],
        body: createUserBody,
        response: { 201: userDto, ...errorResponses(400, 401, 403, 409) },
      },
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
      schema: {
        operationId: 'updateUser',
        security: [{ bearerAuth: [] }],
        params: idParams,
        body: patchUserBody,
        response: { 200: userDto, ...errorResponses(400, 401, 403, 404, 409) },
      },
    },
    async (req) => {
      const { displayName, password, isAdmin } = req.body
      const deleting = req.body.deleted === true
      if (deleting && req.params.id === req.user.id) {
        throw new AppError(409, 'cannot_delete_self', 'Admins cannot delete themselves')
      }
      const passwordHash = password !== undefined ? await hashPassword(password) : undefined

      const updated = await app.db.transaction(async (tx) => {
        // Serialize admin changes so two concurrent demotions cannot remove the last admin.
        await lock(tx, LOCK_USERS)
        await lock(tx, LOCK_SYNC)
        const [target] = await tx.select().from(users).where(eq(users.id, req.params.id))
        if (!target || target.deleted) throw new AppError(404, 'user_not_found', 'User not found')

        // Demoting or deleting an admin must leave at least one other active admin.
        if ((isAdmin === false || deleting) && target.isAdmin) {
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
        if (deleting) changes.deleted = true
        if (Object.keys(changes).length === 0) return target

        const [u] = await tx
          .update(users)
          .set({ ...changes, ...bump() })
          .where(eq(users.id, target.id))
          .returning()
        if (passwordHash !== undefined || deleting) await revokeAllRefreshTokens(tx as unknown as Db, target.id)
        return u!
      })
      return toUserDto(updated)
    },
  )
}
