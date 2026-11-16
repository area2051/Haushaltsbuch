import { createContext, type ReactNode, useCallback, useContext, useEffect, useMemo, useState, useSyncExternalStore } from 'react'
import { ApiClient, type UserDto } from '../api/client'
import { safeStorage } from '../lib/storage'
import { SyncStore, type SyncState } from '../sync/store'
import { type Boot, bootstrap } from './bootstrap'

const REFRESH_KEY = 'hb.refreshToken'
const POLL_MS = 60_000

type Session = { screen: 'checking' } | Boot

type Ctx = {
  api: ApiClient
  store: SyncStore
  session: Session
  user: UserDto | null
  signedIn(user: UserDto): void
  setUser(user: UserDto): void
  signOut(): Promise<void>
  retry(): void
}

const AppCtx = createContext<Ctx | null>(null)

function deviceName(): string {
  const ua = navigator.userAgent
  const browser = /Edg\//.test(ua) ? 'Edge' : /Firefox\//.test(ua) ? 'Firefox' : /Chrome\//.test(ua) ? 'Chrome' : /Safari\//.test(ua) ? 'Safari' : 'Browser'
  const platform = /iPhone|iPad/.test(ua) ? 'iOS' : /Android/.test(ua) ? 'Android' : /Mac/.test(ua) ? 'Mac' : /Windows/.test(ua) ? 'Windows' : ''
  return `Web (${[browser, platform].filter(Boolean).join(', ')})`
}

/** `deps` lets tests wire the provider to a fake server. */
export function AppProvider({ children, deps }: { children: ReactNode; deps?: { api: ApiClient; store: SyncStore } }) {
  const [session, setSession] = useState<Session>({ screen: 'checking' })
  const [attempt, setAttempt] = useState(0)

  const { api, store } = useMemo(() => {
    if (deps) return deps
    const api = new ApiClient({
      tokens: { get: () => safeStorage.get(REFRESH_KEY), set: (t) => safeStorage.set(REFRESH_KEY, t) },
      deviceName: deviceName(),
      onSessionExpired: () => {
        store.reset()
        setSession({ screen: 'login' })
      },
    })
    const store = new SyncStore(api)
    return { api, store }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- created once
  }, [])

  useEffect(() => {
    let cancelled = false
    bootstrap(api)
      .then((b) => !cancelled && setSession(b))
      .catch(() => !cancelled && setSession({ screen: 'unreachable' }))
    return () => {
      cancelled = true
    }
  }, [api, attempt])

  const ready = session.screen === 'ready'
  useEffect(() => {
    if (!ready) return
    const pull = () => void store.pull().catch(() => {})
    pull()
    const timer = setInterval(() => document.visibilityState === 'visible' && pull(), POLL_MS)
    const onVisible = () => document.visibilityState === 'visible' && pull()
    document.addEventListener('visibilitychange', onVisible)
    window.addEventListener('online', pull)
    return () => {
      clearInterval(timer)
      document.removeEventListener('visibilitychange', onVisible)
      window.removeEventListener('online', pull)
    }
  }, [ready, store])

  const signedIn = useCallback((user: UserDto) => setSession({ screen: 'ready', user }), [])
  const setUser = useCallback((user: UserDto) => setSession((s) => (s.screen === 'ready' ? { screen: 'ready', user } : s)), [])
  const signOut = useCallback(async () => {
    await api.logout()
    store.reset()
    setSession({ screen: 'login' })
  }, [api, store])
  const retry = useCallback(() => {
    setSession({ screen: 'checking' })
    setAttempt((a) => a + 1)
  }, [])

  const value = useMemo<Ctx>(
    () => ({ api, store, session, user: session.screen === 'ready' ? session.user : null, signedIn, setUser, signOut, retry }),
    [api, store, session, signedIn, setUser, signOut, retry],
  )
  return <AppCtx.Provider value={value}>{children}</AppCtx.Provider>
}

export function useApp(): Ctx {
  const ctx = useContext(AppCtx)
  if (!ctx) throw new Error('useApp outside AppProvider')
  return ctx
}

/** Signed-in user (only inside the signed-in app). */
export function useMe(): UserDto {
  const { user } = useApp()
  if (!user) throw new Error('useMe without session')
  return user
}

export function useData(): SyncState {
  const { store } = useApp()
  return useSyncExternalStore(store.subscribe, store.getState)
}
