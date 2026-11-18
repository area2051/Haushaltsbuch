// @vitest-environment node
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import openapiTS, { astToString } from 'openapi-typescript'
import { expect, test } from 'vitest'

test('schema.d.ts matches server/openapi.json (run `npm run api` after API changes)', async () => {
  const spec = new URL('../../../server/openapi.json', import.meta.url)
  const generated = astToString(await openapiTS(spec))
  const checkedIn = readFileSync(fileURLToPath(new URL('./schema.d.ts', import.meta.url)), 'utf8')
  const strip = (s: string) => s.replace(/^\/\*\*[\s\S]*?\*\/\n/, '').trim()
  expect(strip(checkedIn)).toBe(strip(generated))
})
