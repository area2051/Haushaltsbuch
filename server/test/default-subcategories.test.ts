import { readdirSync, readFileSync } from 'node:fs'
import { and, eq, isNotNull, isNull, max, sql } from 'drizzle-orm'
import { afterEach, beforeEach, describe, expect, test } from 'vitest'
import { categories } from '../src/db/schema.js'
import { DEFAULT_CATEGORIES } from '../src/setup/defaultCategories.js'
import { createTestApp } from './helpers.js'

const migrationDir = new URL('../drizzle/', import.meta.url)
const file = readdirSync(migrationDir).find((f) => f.endsWith('_default_subcategories.sql'))!
const migrationSql = readFileSync(new URL(file, migrationDir), 'utf8').replaceAll('--> statement-breakpoint', '')

let t: Awaited<ReturnType<typeof createTestApp>>
beforeEach(async () => {
  t = await createTestApp()
})
afterEach(async () => {
  await t.close()
})

const runMigration = () => t.db.execute(sql.raw(migrationSql))
const insertParents = () =>
  t.db
    .insert(categories)
    .values(DEFAULT_CATEGORIES.map(({ children: _c, ...c }, i) => ({ ...c, sortOrder: i })))
    .returning()
const children = () => t.db.select().from(categories).where(isNotNull(categories.parentId))

describe('default subcategories migration', () => {
  test('adds subcategories under untouched default categories', async () => {
    await insertParents()
    const [before] = await t.db.select({ v: max(categories.version) }).from(categories)
    await runMigration()
    const kids = await children()
    expect(kids).toHaveLength(38)
    for (const k of kids) expect(k.version).toBeGreaterThan(before!.v!)
    const strom = kids.find((k) => k.name === 'Strom')!
    const wohnen = DEFAULT_CATEGORIES.find((c) => c.name === 'Wohnen')!
    expect(strom).toMatchObject({ color: wohnen.color, kind: 'expense', icon: 'bolt', sortOrder: 2, deleted: false })
  })

  test('skips renamed or deleted parents', async () => {
    const parents = await insertParents()
    await t.db.update(categories).set({ name: 'Haus' }).where(eq(categories.id, parents.find((p) => p.name === 'Wohnen')!.id))
    await t.db.update(categories).set({ deleted: true }).where(eq(categories.id, parents.find((p) => p.name === 'Abos')!.id))
    await runMigration()
    const kids = await children()
    const parentNames = new Set(kids.map((k) => parents.find((p) => p.id === k.parentId)!.name))
    expect(parentNames.has('Wohnen')).toBe(false)
    expect(parentNames.has('Abos')).toBe(false)
    expect(kids).toHaveLength(38 - 9 - 4)
  })

  test('skips parents that already have children', async () => {
    const parents = await insertParents()
    const wohnen = parents.find((p) => p.name === 'Wohnen')!
    await t.db.insert(categories).values({ name: 'Eigene', icon: 'house', color: wohnen.color, kind: 'expense', parentId: wohnen.id })
    await runMigration()
    const kids = await children()
    expect(kids.filter((k) => k.parentId === wohnen.id).map((k) => k.name)).toEqual(['Eigene'])
    expect(kids).toHaveLength(38 - 9 + 1)
  })

  test('skips names that already exist for that kind', async () => {
    await insertParents()
    await t.db.insert(categories).values({ name: 'strom', icon: 'bolt', color: '#000000', kind: 'expense' })
    await runMigration()
    const kids = await children()
    expect(kids.some((k) => k.name === 'Strom')).toBe(false)
    expect(kids.filter((k) => k.name === 'Gas')).toHaveLength(1)
    expect(kids).toHaveLength(37)
  })

  test('second run adds nothing', async () => {
    await insertParents()
    await runMigration()
    await runMigration()
    expect(await children()).toHaveLength(38)
  })

  test('is a no-op on an empty database', async () => {
    await runMigration()
    expect(await t.db.select().from(categories)).toHaveLength(0)
  })

  test('matches DEFAULT_CATEGORIES', async () => {
    const parents = await insertParents()
    await runMigration()
    const kids = await t.db.select().from(categories).where(and(isNotNull(categories.parentId)))
    for (const [i, def] of DEFAULT_CATEGORIES.entries()) {
      const parent = parents.find((p) => p.name === def.name)!
      const got = kids.filter((k) => k.parentId === parent.id).sort((a, b) => a.sortOrder - b.sortOrder)
      expect(got.map((k) => ({ name: k.name, icon: k.icon }))).toEqual(def.children ?? [])
      expect(got.map((k) => k.sortOrder)).toEqual((def.children ?? []).map((_, j) => j))
      for (const k of got) expect(k).toMatchObject({ color: def.color, kind: def.kind })
      expect(i).toBeGreaterThanOrEqual(0)
    }
    expect(await t.db.select().from(categories).where(isNull(categories.parentId))).toHaveLength(10)
  })
})
