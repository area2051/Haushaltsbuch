import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify'
import { AppError } from '../errors.js'
import { type AuthUser, verifyAccessToken } from './tokens.js'

/**
 * Adds the `authenticate` and `requireAdmin` decorators directly on the given
 * instance (called from buildApp, not via `register`, so they are visible to
 * every route). `authenticate` trusts the verified JWT claims; there is no DB
 * lookup per request.
 */
export function registerAuth(app: FastifyInstance): void {
  app.decorateRequest('user', null as unknown as AuthUser)

  app.decorate('authenticate', async function authenticate(req: FastifyRequest, _reply: FastifyReply) {
    const header = req.headers.authorization
    const match = header ? /^Bearer ([^\s]+)$/i.exec(header) : null
    const user = match ? await verifyAccessToken(app.config.jwtSecret, app.clock, match[1]!) : null
    if (!user) throw new AppError(401, 'unauthorized', 'Missing or invalid access token')
    req.user = user
  })

  app.decorate('requireAdmin', async function requireAdmin(req: FastifyRequest, _reply: FastifyReply) {
    if (!req.user) throw new AppError(401, 'unauthorized', 'Missing or invalid access token')
    if (!req.user.isAdmin) throw new AppError(403, 'forbidden', 'Admin privileges required')
  })
}

declare module 'fastify' {
  interface FastifyInstance {
    authenticate(req: FastifyRequest, reply: FastifyReply): Promise<void>
    requireAdmin(req: FastifyRequest, reply: FastifyReply): Promise<void>
  }
  interface FastifyRequest {
    /** Set by `app.authenticate`; only use in routes that run it as a preHandler. */
    user: AuthUser
  }
}
