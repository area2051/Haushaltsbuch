import { existsSync } from 'node:fs'
import { extname, join, resolve, sep } from 'node:path'
import fastifyStatic from '@fastify/static'
import type { FastifyInstance, FastifyReply } from 'fastify'

/** Mount point of the web app. Kept off `/` so SPA paths never collide with API paths like `/users`. */
export const WEB_PREFIX = '/app/'

const CSP = [
  "default-src 'self'",
  "img-src 'self' data:",
  // Charts and animations set inline style attributes.
  "style-src 'self' 'unsafe-inline'",
  "font-src 'self'",
  "connect-src 'self'",
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "frame-ancestors 'none'",
].join('; ')

/** True when `dir` holds a built web app (an `index.html`). */
export function hasWebApp(dir: string | undefined): dir is string {
  return !!dir && existsSync(join(dir, 'index.html'))
}

const HTML_HEADERS: Record<string, string> = {
  'Cache-Control': 'no-cache',
  'Content-Security-Policy': CSP,
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
}

function sendIndex(reply: FastifyReply) {
  return reply.headers(HTML_HEADERS).sendFile('index.html')
}

/**
 * Serves the built web app (Vite output) under `/app/`. Files are hashed, so `/app/assets/*`
 * is cached forever; `index.html` is always revalidated. Unknown extension-less paths fall back
 * to `index.html` for client-side routing. None of these routes appear in `openapi.json`.
 */
export async function webRoutes(app: FastifyInstance, opts: { root: string }): Promise<void> {
  const root = resolve(opts.root)
  const assets = join(root, 'assets') + sep

  await app.register(fastifyStatic, {
    root,
    prefix: WEB_PREFIX,
    // One route per file at startup; lets the fallback below catch everything else.
    wildcard: false,
    index: false,
    schemaHide: true,
    // Cache-Control is set per file below.
    cacheControl: false,
    setHeaders(res, path) {
      if (path.endsWith('.html')) {
        // Also /app/index.html requested directly, which the plugin serves itself.
        for (const [k, v] of Object.entries(HTML_HEADERS)) res.setHeader(k, v)
        return
      }
      res.setHeader('X-Content-Type-Options', 'nosniff')
      res.setHeader('Cache-Control', path.startsWith(assets) ? 'public, max-age=31536000, immutable' : 'no-cache')
    },
  })

  const hide = { schema: { hide: true } }
  app.get('/', hide, (_req, reply) => reply.redirect(WEB_PREFIX))
  app.get('/app', hide, (_req, reply) => reply.redirect(WEB_PREFIX))
  app.get(WEB_PREFIX, hide, (_req, reply) => sendIndex(reply))
  app.get(`${WEB_PREFIX}*`, hide, (req, reply) => {
    // A missing asset is a real 404, not the app shell.
    const path = req.url.split('?')[0] ?? ''
    if (extname(path) !== '') return reply.callNotFound()
    return sendIndex(reply)
  })
}
