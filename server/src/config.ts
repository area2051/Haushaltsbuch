export type Config = {
  databaseUrl: string
  jwtSecret: string
  port: number
  timeZone: string
  /** Directory with the built web app; served under /app/ when it contains an index.html. */
  webDir?: string
}

export function loadConfig(env: NodeJS.ProcessEnv): Config {
  const databaseUrl = env.DATABASE_URL
  if (!databaseUrl) throw new Error('DATABASE_URL is required')

  const jwtSecret = env.JWT_SECRET
  if (!jwtSecret) throw new Error('JWT_SECRET is required')
  if (jwtSecret.length < 32) throw new Error('JWT_SECRET must be at least 32 characters')

  const port = env.PORT ? Number(env.PORT) : 3000
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('PORT must be an integer between 1 and 65535')
  }

  return {
    databaseUrl,
    jwtSecret,
    port,
    timeZone: env.TZ || 'Europe/Berlin',
    webDir: env.WEB_DIR || 'web-dist',
  }
}
