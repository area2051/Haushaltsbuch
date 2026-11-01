import { readFileSync } from 'node:fs'
import { afterAll, beforeAll, describe, expect, test } from 'vitest'
import { stableSpec } from '../src/openapi/stableSpec.js'
import { createTestApp } from './helpers.js'

type Op = {
  operationId?: string
  security?: unknown[]
  responses: Record<string, { content?: Record<string, { schema?: { $ref?: string } }> }>
}
type Spec = {
  openapi: string
  paths: Record<string, Record<string, Op>>
  components: {
    schemas: Record<string, { properties?: Record<string, { format?: string; type?: string | string[] }> }>
    securitySchemes: Record<string, unknown>
  }
}

let t: Awaited<ReturnType<typeof createTestApp>>
let spec: Spec

beforeAll(async () => {
  t = await createTestApp()
  await t.app.ready()
  spec = stableSpec(t.app.swagger()) as Spec
})
afterAll(async () => {
  await t.close()
})

const ops = () =>
  Object.entries(spec.paths).flatMap(([path, item]) =>
    Object.entries(item).map(([method, op]) => ({ path, method, op })),
  )

describe('openapi', () => {
  test('checked-in openapi.json is up to date', () => {
    expect(JSON.parse(readFileSync('openapi.json', 'utf8'))).toEqual(spec)
  })

  test('objects are open, uuid has no pattern, no const', () => {
    const json = JSON.stringify(spec)
    expect(json).not.toContain('"additionalProperties":false')
    expect(json).not.toContain('"const"')
    expect(json).not.toContain('Input"')
    expect(spec.components.schemas.CategoryRecord!.properties!.id).not.toHaveProperty('pattern')
  })

  test('nullable fields use type arrays, not anyOf with null (swift-openapi-generator drops those)', () => {
    expect(JSON.stringify(spec).includes('{"type":"null"}')).toBe(false)
    const props = (name: string) => spec.components.schemas[name]!.properties!
    expect(props('TransactionRecord').note).toEqual({ type: ['string', 'null'], maxLength: 200 })
    expect(props('TransactionRecord').recurringRuleId).toEqual({ type: ['string', 'null'], format: 'uuid' })
    expect(props('TransactionRecordOut').recurringRuleId).toEqual({ type: ['string', 'null'], format: 'uuid' })
    expect(props('RecurringRuleRecord').note).toEqual({ type: ['string', 'null'], maxLength: 200 })
    expect(props('RecurringRuleRecord').endDate).toEqual({ type: ['string', 'null'], pattern: '^\\d{4}-\\d{2}-\\d{2}$' })
    expect(props('RecurringRuleRecordOut').endDate).toEqual({ type: ['string', 'null'], pattern: '^\\d{4}-\\d{2}-\\d{2}$' })
  })

  test('is OpenAPI 3.1', () => {
    expect(spec.openapi).toMatch(/^3\.1/)
  })

  test('every route has the expected operationId', () => {
    const ids = Object.fromEntries(ops().map(({ path, method, op }) => [`${method.toUpperCase()} ${path}`, op.operationId]))
    expect(ids).toEqual({
      'GET /health': 'getHealth',
      'POST /setup': 'setup',
      'POST /auth/login': 'login',
      'POST /auth/refresh': 'refresh',
      'POST /auth/logout': 'logout',
      'GET /me': 'getMe',
      'PATCH /me': 'updateMe',
      'GET /users': 'listUsers',
      'POST /users': 'createUser',
      'PATCH /users/{id}': 'updateUser',
      'POST /sync': 'sync',
    })
  })

  test('named components exist', () => {
    for (const name of [
      'UserDto',
      'ErrorResponse',
      'CategoryRecord',
      'TransactionRecord',
      'BudgetRecord',
      'RecurringRuleRecord',
      'UserRecord',
      'SyncRequest',
      'SyncResponse',
    ]) {
      expect(spec.components.schemas[name], name).toBeDefined()
    }
  })

  test('uuid fields keep format uuid', () => {
    expect(spec.components.schemas.CategoryRecord!.properties!.id).toMatchObject({ type: 'string', format: 'uuid' })
  })

  test('sync documents typed records via refs', () => {
    const sync = spec.paths['/sync']!.post!
    expect(sync.responses['200']!.content!['application/json']!.schema!.$ref).toBe('#/components/schemas/SyncResponse')
    expect(JSON.stringify(spec.components.schemas.SyncRequest)).toContain('#/components/schemas/CategoryRecord')
  })

  test('bearerAuth is applied exactly to authenticated routes', () => {
    expect(spec.components.securitySchemes.bearerAuth).toMatchObject({ type: 'http', scheme: 'bearer', bearerFormat: 'JWT' })
    const secured = ops()
      .filter(({ op }) => op.security?.length)
      .map(({ path, method }) => `${method.toUpperCase()} ${path}`)
      .sort()
    expect(secured).toEqual(
      ['POST /auth/logout', 'GET /me', 'PATCH /me', 'GET /users', 'POST /users', 'PATCH /users/{id}', 'POST /sync'].sort(),
    )
  })

  test('error responses use ErrorResponse', () => {
    const ref = (path: string, method: string, code: string) =>
      spec.paths[path]![method]!.responses[code]?.content?.['application/json']?.schema?.$ref
    const E = '#/components/schemas/ErrorResponse'
    expect(ref('/auth/login', 'post', '401')).toBe(E)
    expect(ref('/auth/login', 'post', '429')).toBe(E)
    expect(ref('/setup', 'post', '409')).toBe(E)
    expect(ref('/users', 'get', '403')).toBe(E)
    expect(ref('/users/{id}', 'patch', '404')).toBe(E)
    expect(ref('/users/{id}', 'patch', '409')).toBe(E)
    expect(ref('/sync', 'post', '400')).toBe(E)
    for (const { op } of ops()) expect(op.responses['500']).toBeDefined()
  })
})
