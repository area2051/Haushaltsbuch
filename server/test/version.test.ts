import { readFileSync } from 'node:fs'
import { expect, test } from 'vitest'
import { APP_VERSION } from '../src/version.js'

const readVersion = (rel: string): string =>
  (JSON.parse(readFileSync(new URL(rel, import.meta.url), 'utf8')) as { version: string }).version

test('APP_VERSION equals the version in server/package.json and has X.Y.Z format', () => {
  expect(APP_VERSION).toBe(readVersion('../package.json'))
  expect(APP_VERSION).toMatch(/^\d+\.\d+\.\d+$/)
})

test('server and web package versions are identical', () => {
  expect(readVersion('../package.json')).toBe(readVersion('../../web/package.json'))
})
