import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import type { FastifyInstance } from 'fastify'
import { afterAll, afterEach, beforeAll, expect, test } from 'vitest'
import { createTestApp } from './helpers.js'

let webDir: string
let closeApp: (() => Promise<void>) | undefined

beforeAll(() => {
  webDir = mkdtempSync(join(tmpdir(), 'hb-web-'))
  mkdirSync(join(webDir, 'assets'))
  writeFileSync(join(webDir, 'index.html'), '<!doctype html><title>Haushaltsbuch</title>')
  writeFileSync(join(webDir, 'assets', 'app-abc.js'), 'console.log(1)')
  writeFileSync(join(webDir, 'manifest.webmanifest'), '{}')
  mkdirSync(join(webDir, 'assets-extra'))
  writeFileSync(join(webDir, 'assets-extra', 'x.js'), '1')
})
afterAll(() => rmSync(webDir, { recursive: true, force: true }))
afterEach(async () => {
  await closeApp?.()
  closeApp = undefined
})

async function makeApp(dir: string | undefined): Promise<FastifyInstance> {
  const ctx = await createTestApp({ webDir: dir })
  closeApp = ctx.close
  return ctx.app
}

test('serves the app shell under /app/ with security headers', async () => {
  const app = await makeApp(webDir)
  const res = await app.inject({ method: 'GET', url: '/app/' })
  expect(res.statusCode).toBe(200)
  expect(res.headers['content-type']).toContain('text/html')
  expect(res.body).toContain('Haushaltsbuch')
  expect(res.headers['content-security-policy']).toContain("frame-ancestors 'none'")
  expect(res.headers['cache-control']).toBe('no-cache')
})

test('client-side routes fall back to index.html', async () => {
  const app = await makeApp(webDir)
  const res = await app.inject({ method: 'GET', url: '/app/buchungen?monat=2026-11' })
  expect(res.statusCode).toBe(200)
  expect(res.body).toContain('Haushaltsbuch')
})

test('hashed assets are cached, missing assets are 404', async () => {
  const app = await makeApp(webDir)
  const asset = await app.inject({ method: 'GET', url: '/app/assets/app-abc.js' })
  expect(asset.statusCode).toBe(200)
  expect(asset.headers['cache-control']).toContain('immutable')
  const missing = await app.inject({ method: 'GET', url: '/app/assets/nope.js' })
  expect(missing.statusCode).toBe(404)
  expect(missing.json().error.code).toBe('not_found')
})

test('root and /app redirect to /app/', async () => {
  const app = await makeApp(webDir)
  for (const url of ['/', '/app']) {
    const res = await app.inject({ method: 'GET', url })
    expect(res.statusCode).toBe(302)
    expect(res.headers.location).toBe('/app/')
  }
})

test('API routes are unaffected', async () => {
  const app = await makeApp(webDir)
  const res = await app.inject({ method: 'GET', url: '/health' })
  expect(res.statusCode).toBe(200)
  expect(res.json()).toHaveProperty('setupRequired')
})

test('without a built web app no web routes exist', async () => {
  const app = await makeApp(join(webDir, 'does-not-exist'))
  expect((await app.inject({ method: 'GET', url: '/app/' })).statusCode).toBe(404)
  expect((await app.inject({ method: 'GET', url: '/' })).statusCode).toBe(404)
})

test('index.html requested directly also carries the security headers', async () => {
  const app = await makeApp(webDir)
  const res = await app.inject({ method: 'GET', url: '/app/index.html' })
  expect(res.statusCode).toBe(200)
  expect(res.headers['content-security-policy']).toContain("frame-ancestors 'none'")
})

test('only files inside assets/ are cached forever', async () => {
  const app = await makeApp(webDir)
  const res = await app.inject({ method: 'GET', url: '/app/assets-extra/x.js' })
  expect(res.statusCode).toBe(200)
  expect(res.headers['cache-control']).toBe('no-cache')
})
