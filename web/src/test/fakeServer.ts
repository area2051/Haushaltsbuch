import type { components } from '../api/schema'

type User = components['schemas']['UserDto']

/**
 * In-memory stand-in for the parts of the API the client's auth logic depends on:
 * token issuing, rotation and expiry, plus the error envelope. Records every request.
 */
export class FakeServer {
  user: User = { id: 'u1', username: 'anna', displayName: 'Anna', isAdmin: true }
  password = 'geheim123'
  validAccess = new Set<string>()
  validRefresh = new Set<string>()
  revoked: string[] = []
  requests: Array<{ method: string; path: string; auth: string | null; body: unknown }> = []
  /** When true every request fails at the network level. */
  offline = false
  setupRequired = false
  /** Handles POST /sync when set (see FakeSyncServer). */
  syncHandler: ((body: never) => Promise<unknown>) | null = null
  /** Artificial delay for refresh calls, to test concurrent 401s. */
  refreshDelayMs = 0
  private n = 0

  issue(): { accessToken: string; refreshToken: string } {
    const pair = { accessToken: `a${++this.n}`, refreshToken: `r${this.n}` }
    this.validAccess.add(pair.accessToken)
    this.validRefresh.add(pair.refreshToken)
    return pair
  }

  expireAccessTokens(): void {
    this.validAccess.clear()
  }

  fetch = async (input: string | URL | Request, init: RequestInit = {}): Promise<Response> => {
    if (this.offline) throw new TypeError('Failed to fetch')
    const path = String(input)
    const method = init.method ?? 'GET'
    const headers = new Headers(init.headers)
    const body = init.body ? JSON.parse(String(init.body)) : undefined
    this.requests.push({ method, path, auth: headers.get('Authorization'), body })

    const json = (status: number, data: unknown) =>
      new Response(status === 204 ? null : JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } })
    const error = (status: number, code: string) => json(status, { error: { code, message: code } })
    const authed = () => {
      const token = headers.get('Authorization')?.replace('Bearer ', '') ?? ''
      return this.validAccess.has(token)
    }

    if (path === '/health') return json(200, { status: 'ok', setupRequired: this.setupRequired })
    if (path === '/auth/login') {
      if (body.username !== this.user.username || body.password !== this.password) return error(401, 'invalid_credentials')
      return json(200, { ...this.issue(), user: this.user })
    }
    if (path === '/auth/refresh') {
      if (this.refreshDelayMs) await new Promise((r) => setTimeout(r, this.refreshDelayMs))
      if (!this.validRefresh.delete(body.refreshToken)) return error(401, 'invalid_refresh_token')
      return json(200, this.issue())
    }
    if (!authed()) return error(401, 'unauthorized')
    if (path === '/auth/logout') {
      this.revoked.push(body.refreshToken)
      this.validRefresh.delete(body.refreshToken)
      return json(204, null)
    }
    if (path === '/me' && method === 'PATCH') return json(200, { ...this.user, ...(body.displayName ? { displayName: body.displayName } : {}) })
    if (path === '/me') return json(200, this.user)
    if (path === '/sync' && this.syncHandler) return json(200, await this.syncHandler(body as never))
    if (path === '/users') return error(403, 'forbidden')
    return error(404, 'not_found')
  }
}

/** Refresh-token storage backed by a plain variable (instead of localStorage). */
export function memoryTokenStore(initial: string | null = null) {
  let value = initial
  return { get: () => value, set: (t: string | null) => void (value = t) }
}
