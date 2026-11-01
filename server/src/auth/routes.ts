import { eq } from 'drizzle-orm'
import type { FastifyInstance } from 'fastify'
import type { ZodTypeProvider } from 'fastify-type-provider-zod'
import { z } from 'zod'
import { users } from '../db/schema.js'
import { AppError, errorResponses } from '../errors.js'
import { toUserDto, userDto } from '../users/dto.js'
import { createLoginLimiter } from './loginLimiter.js'
import { hashPassword, verifyPassword } from './passwords.js'
import { issueRefreshToken, revokeRefreshToken, rotateRefreshToken, signAccessToken } from './tokens.js'

const loginBody = z.object({
  username: z.string().min(1).max(64),
  password: z.string().min(1).max(1024),
  deviceName: z.string().max(100).optional(),
}).meta({ id: 'LoginRequest' })

const refreshBody = z.object({ refreshToken: z.string().min(1).max(256) }).meta({ id: 'RefreshRequest' })

const tokenPair = z.object({ accessToken: z.string(), refreshToken: z.string() }).meta({ id: 'TokenPair' })

export async function authRoutes(app: FastifyInstance): Promise<void> {
  const r = app.withTypeProvider<ZodTypeProvider>()
  const limiter = createLoginLimiter(app.clock)
  // Verified against for unknown usernames so response timing does not reveal which usernames exist.
  const dummyHash = await hashPassword('dummy-password-for-timing')

  r.post(
    '/auth/login',
    {
      schema: {
        operationId: 'login',
        security: [],
        body: loginBody,
        response: {
          200: tokenPair.extend({ user: userDto }).meta({ id: 'LoginResponse' }),
          ...errorResponses(400, 401, 429),
        },
      },
    },
    async (req) => {
      const { username, password, deviceName } = req.body
      limiter.check(username)

      let user: typeof users.$inferSelect | undefined
      let ok: boolean
      try {
        ;[user] = await app.db.select().from(users).where(eq(users.username, username))
        ok = await verifyPassword(user?.passwordHash ?? dummyHash, password)
      } catch (e) {
        limiter.release(username)
        throw e
      }
      if (!user || !ok || user.deleted) {
        limiter.fail(username)
        throw new AppError(401, 'invalid_credentials', 'Invalid username or password')
      }
      limiter.reset(username)

      const accessToken = await signAccessToken(app.config.jwtSecret, app.clock, user)
      const refreshToken = await issueRefreshToken(app.db, app.clock, user.id, deviceName ?? null)
      return {
        accessToken,
        refreshToken,
        user: toUserDto(user),
      }
    },
  )

  r.post(
    '/auth/refresh',
    {
      schema: {
        operationId: 'refresh',
        security: [],
        body: refreshBody,
        response: { 200: tokenPair, ...errorResponses(400, 401) },
      },
    },
    async (req) => {
      const rotated = await rotateRefreshToken(app.db, app.clock, req.body.refreshToken)
      if (!rotated) throw new AppError(401, 'invalid_refresh_token', 'Refresh token is invalid or expired')
      const accessToken = await signAccessToken(app.config.jwtSecret, app.clock, rotated.user)
      return { accessToken, refreshToken: rotated.refreshToken }
    },
  )

  r.post(
    '/auth/logout',
    {
      onRequest: app.authenticate,
      schema: {
        operationId: 'logout',
        security: [{ bearerAuth: [] }],
        body: refreshBody,
        response: { 204: z.null().describe('Logged out'), ...errorResponses(400, 401) },
      },
    },
    async (req, reply) => {
      await revokeRefreshToken(app.db, req.user.id, req.body.refreshToken)
      return reply.status(204).send(null)
    },
  )
}
