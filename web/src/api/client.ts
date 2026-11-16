import type { components } from './schema'

type S = components['schemas']
export type UserDto = S['UserDto']

/** Where the refresh token lives between page loads (localStorage in the app). */
export type TokenStore = { get(): string | null; set(token: string | null): void }

/** Failed API call. `code` is the server's `error.code`, or `unreachable` for network failures. */
export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
  ) {
    super(code)
    this.name = 'ApiError'
  }
}

type Options = {
  fetch?: typeof fetch
  tokens: TokenStore
  deviceName: string
  /** Called when the refresh token is rejected; the app then shows the login screen. */
  onSessionExpired?: () => void
}

/**
 * Typed client for the Haushaltsbuch API on the same origin.
 * The access token lives only in memory; it is (re)issued from the stored refresh token on
 * demand and after a 401. Concurrent requests share one refresh (tokens rotate on refresh).
 */
export class ApiClient {
  private readonly fetchFn: typeof fetch
  private accessToken: string | null = null
  private refreshing: Promise<void> | null = null

  constructor(private readonly opts: Options) {
    this.fetchFn = opts.fetch ?? ((input, init) => globalThis.fetch(input, init))
  }

  hasSession(): boolean {
    return this.opts.tokens.get() !== null
  }

  // ---- public endpoints ----

  health(): Promise<S['HealthResponse']> {
    return this.call('GET', '/health')
  }

  setup(body: S['SetupRequest']): Promise<S['SetupResponse']> {
    return this.call('POST', '/setup', body)
  }

  async login(username: string, password: string): Promise<UserDto> {
    const res = await this.call<S['LoginResponse']>('POST', '/auth/login', {
      username,
      password,
      deviceName: this.opts.deviceName,
    })
    this.accessToken = res.accessToken
    this.opts.tokens.set(res.refreshToken)
    return res.user
  }

  /** Revokes the refresh token on the server (best effort) and always clears the local session. */
  async logout(): Promise<void> {
    try {
      // Body is built per attempt: a refresh inside `authed` rotates the token.
      if (this.opts.tokens.get()) await this.authed('POST', '/auth/logout', () => ({ refreshToken: this.opts.tokens.get() }))
    } catch {
      // Offline or already invalid: the local session is cleared anyway.
    } finally {
      this.clearSession()
    }
  }

  // ---- authenticated endpoints ----

  me(): Promise<UserDto> {
    return this.authed('GET', '/me')
  }

  /** A password change revokes the user's other sessions but keeps this one. */
  updateMe(body: S['UpdateMeRequest']): Promise<UserDto> {
    if (!body.newPassword) return this.authed('PATCH', '/me', body)
    // Read the token per attempt: a refresh before the retry rotates it.
    return this.authed('PATCH', '/me', () => ({ ...body, keepRefreshToken: this.opts.tokens.get() ?? undefined }))
  }

  users(): Promise<UserDto[]> {
    return this.authed('GET', '/users')
  }

  createUser(body: S['CreateUserRequest']): Promise<UserDto> {
    return this.authed('POST', '/users', body)
  }

  updateUser(id: string, body: S['UpdateUserRequest']): Promise<UserDto> {
    return this.authed('PATCH', `/users/${encodeURIComponent(id)}`, body)
  }

  sync(body: S['SyncRequest']): Promise<S['SyncResponse']> {
    return this.authed('POST', '/sync', body)
  }

  // ---- plumbing ----

  private clearSession(): void {
    this.accessToken = null
    this.opts.tokens.set(null)
  }

  /** `body` may be a function, evaluated for each attempt (after a possible refresh). */
  private async authed<T>(method: string, path: string, body?: unknown): Promise<T> {
    const make = () => (typeof body === 'function' ? (body as () => unknown)() : body)
    if (!this.accessToken) await this.refresh()
    const token = this.accessToken
    try {
      return await this.call<T>(method, path, make(), token)
    } catch (e) {
      if (!(e instanceof ApiError) || e.status !== 401) throw e
      // Another request may already have refreshed while this one was in flight.
      if (this.accessToken === token) await this.refresh()
      return this.call<T>(method, path, make(), this.accessToken)
    }
  }

  private refresh(): Promise<void> {
    this.refreshing ??= this.doRefresh().finally(() => {
      this.refreshing = null
    })
    return this.refreshing
  }

  private async doRefresh(): Promise<void> {
    const refreshToken = this.opts.tokens.get()
    if (!refreshToken) throw new ApiError(401, 'unauthorized')
    try {
      const pair = await this.call<S['TokenPair']>('POST', '/auth/refresh', { refreshToken })
      this.accessToken = pair.accessToken
      this.opts.tokens.set(pair.refreshToken)
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) {
        this.clearSession()
        this.opts.onSessionExpired?.()
        throw new ApiError(401, 'unauthorized')
      }
      throw e
    }
  }

  private async call<T>(method: string, path: string, body?: unknown, token?: string | null): Promise<T> {
    const headers: Record<string, string> = { Accept: 'application/json' }
    if (body !== undefined) headers['Content-Type'] = 'application/json'
    if (token) headers.Authorization = `Bearer ${token}`

    let res: Response
    try {
      res = await this.fetchFn(path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) })
    } catch {
      throw new ApiError(0, 'unreachable')
    }
    if (res.status === 204) return undefined as T
    const data: unknown = await res.json().catch(() => null)
    if (!res.ok) {
      const code = (data as { error?: { code?: string } } | null)?.error?.code ?? 'internal'
      throw new ApiError(res.status, code)
    }
    return data as T
  }
}
