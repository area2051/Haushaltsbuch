import { createHash, randomBytes } from 'node:crypto'
import { and, eq, lte } from 'drizzle-orm'
import { jwtVerify, SignJWT } from 'jose'
import type { Clock } from '../clock.js'
import type { Db } from '../db/client.js'
import { refreshTokens, users } from '../db/schema.js'

export const ACCESS_TOKEN_TTL_SECONDS = 15 * 60
export const REFRESH_TOKEN_TTL_MS = 90 * 24 * 60 * 60 * 1000

export type AuthUser = { id: string; isAdmin: boolean }

function secretKey(secret: string): Uint8Array {
  return new TextEncoder().encode(secret)
}

export async function signAccessToken(secret: string, clock: Clock, user: AuthUser): Promise<string> {
  const iat = Math.floor(clock.now().getTime() / 1000)
  return new SignJWT({ admin: user.isAdmin })
    .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
    .setSubject(user.id)
    .setIssuedAt(iat)
    .setExpirationTime(iat + ACCESS_TOKEN_TTL_SECONDS)
    .sign(secretKey(secret))
}

/** Returns the authenticated user, or null if the token is invalid or expired. */
export async function verifyAccessToken(secret: string, clock: Clock, token: string): Promise<AuthUser | null> {
  try {
    const { payload } = await jwtVerify(token, secretKey(secret), {
      algorithms: ['HS256'],
      currentDate: clock.now(),
      requiredClaims: ['sub', 'exp'],
    })
    if (typeof payload.sub !== 'string' || typeof payload.admin !== 'boolean') return null
    return { id: payload.sub, isAdmin: payload.admin }
  } catch {
    return null
  }
}

export function hashRefreshToken(token: string): string {
  return createHash('sha256').update(token).digest('hex')
}

function newRefreshToken(): string {
  return randomBytes(32).toString('base64url')
}

type Executor = Pick<Db, 'insert'>

async function insertRefreshToken(
  db: Executor,
  clock: Clock,
  userId: string,
  deviceName: string | null,
): Promise<string> {
  const token = newRefreshToken()
  const now = clock.now()
  await db.insert(refreshTokens).values({
    userId,
    tokenHash: hashRefreshToken(token),
    expiresAt: new Date(now.getTime() + REFRESH_TOKEN_TTL_MS),
    deviceName,
    createdAt: now,
  })
  return token
}

export function issueRefreshToken(
  db: Db,
  clock: Clock,
  userId: string,
  deviceName: string | null,
): Promise<string> {
  return insertRefreshToken(db, clock, userId, deviceName)
}

/**
 * Consumes a refresh token and issues a new one in a single transaction.
 * The old row is deleted first, so a replayed or concurrently used token finds
 * nothing and yields null. Expired tokens and tokens of deleted users are
 * removed and yield null as well.
 */
export async function rotateRefreshToken(
  db: Db,
  clock: Clock,
  token: string,
): Promise<{ user: AuthUser; refreshToken: string } | null> {
  return db.transaction(async (tx) => {
    const [old] = await tx
      .delete(refreshTokens)
      .where(eq(refreshTokens.tokenHash, hashRefreshToken(token)))
      .returning()
    if (!old) return null
    if (old.expiresAt.getTime() <= clock.now().getTime()) return null

    const [user] = await tx
      .select({ id: users.id, isAdmin: users.isAdmin, deleted: users.deleted })
      .from(users)
      .where(eq(users.id, old.userId))
    if (!user || user.deleted) return null

    const refreshToken = await insertRefreshToken(tx, clock, user.id, old.deviceName)
    return { user: { id: user.id, isAdmin: user.isAdmin }, refreshToken }
  })
}

/** Deletes the refresh token if it belongs to the given user. */
export async function revokeRefreshToken(db: Db, userId: string, token: string): Promise<void> {
  await db
    .delete(refreshTokens)
    .where(and(eq(refreshTokens.tokenHash, hashRefreshToken(token)), eq(refreshTokens.userId, userId)))
}

/**
 * Deletes refresh tokens that expired at or before `now` (same rule as `rotateRefreshToken`).
 * Called by the daily scheduler tick. Returns the number of deleted tokens.
 */
export async function pruneExpiredRefreshTokens(db: Db, now: Date): Promise<number> {
  const deleted = await db
    .delete(refreshTokens)
    .where(lte(refreshTokens.expiresAt, now))
    .returning({ id: refreshTokens.id })
  return deleted.length
}
