import { ApiError, type ApiClient, type UserDto } from '../api/client'

export type Boot = { screen: 'ready'; user: UserDto } | { screen: 'setup' | 'login' | 'unreachable' }

const unreachable = (e: unknown) => e instanceof ApiError && e.code === 'unreachable'

/** Decides the first screen: the app (stored session still valid), setup, login, or offline notice. */
export async function bootstrap(api: ApiClient): Promise<Boot> {
  if (api.hasSession()) {
    try {
      return { screen: 'ready', user: await api.me() }
    } catch (e) {
      if (unreachable(e)) return { screen: 'unreachable' }
      if (!(e instanceof ApiError) || e.status !== 401) throw e
    }
  }
  try {
    const health = await api.health()
    return { screen: health.setupRequired ? 'setup' : 'login' }
  } catch (e) {
    if (unreachable(e)) return { screen: 'unreachable' }
    throw e
  }
}
