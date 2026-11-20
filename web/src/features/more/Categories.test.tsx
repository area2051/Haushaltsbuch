import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test } from 'vitest'
import { renderSignedIn } from '../../test/renderApp'
import type { FakeSyncServer } from '../../test/fakeSync'
import { Categories } from './Categories'

const category = (id: string, name: string, sortOrder: number, extra: Record<string, unknown> = {}) => ({
  id, name, icon: 'cart', color: '#4CAF50', kind: 'expense', sortOrder, parentId: null, archived: false, deleted: false, ...extra,
})

async function setup(seed: (sync: FakeSyncServer) => void = () => {}) {
  const ctx = await renderSignedIn(<Categories />, {
    seed: (sync) => {
      sync.put('categories', category('c-home', 'Wohnen', 0, { color: '#795548' }))
      sync.put('categories', category('c-power', 'Strom', 0, { parentId: 'c-home', color: '#795548' }))
      sync.put('categories', category('c-food', 'Lebensmittel', 1))
      seed(sync)
    },
  })
  return { ...ctx, user: userEvent.setup() }
}

const pushed = (sync: FakeSyncServer) => sync.requests.flatMap((r) => r.changes.categories ?? [])
const open = async (user: ReturnType<typeof userEvent.setup>, name: string) => {
  await user.click(await screen.findByRole('button', { name }))
  return within(await screen.findByRole('dialog'))
}

test('subcategories are listed indented right under their main category', async () => {
  await setup()
  const rows = (await screen.findAllByRole('listitem')).map((li) => li.textContent)
  expect(rows).toEqual(['Wohnen', 'Strom', 'Lebensmittel'])
  expect(screen.getAllByRole('listitem')[1]).toHaveClass('ml-8')
})

test('a main category with subcategories cannot be deleted', async () => {
  const { user } = await setup()
  const dialog = await open(user, 'Wohnen')
  expect(dialog.getByRole('button', { name: 'Erst Unterkategorien entfernen' })).toBeDisabled()
  expect(dialog.queryByRole('button', { name: 'Löschen' })).toBeNull()
  // It cannot become a subcategory itself either.
  expect(dialog.queryByLabelText('Gehört zu')).toBeNull()
})

test('moving a category with a budget under a main category without one says the budget moves along', async () => {
  const { user, sync } = await setup((s) => s.put('budgets', { id: 'b-food', categoryId: 'c-food', monthlyLimitCents: 30000, deleted: false }))
  const dialog = await open(user, 'Lebensmittel')
  expect(dialog.getByRole('option', { name: 'Keine (Hauptkategorie)' })).toBeInTheDocument()
  await user.selectOptions(dialog.getByLabelText('Gehört zu'), 'Wohnen')
  expect(dialog.getByText('Das Budget geht auf Wohnen über.')).toBeInTheDocument()

  await user.click(dialog.getByRole('button', { name: 'Speichern' }))
  await waitFor(() => expect(pushed(sync)).toHaveLength(1))
  expect(pushed(sync)[0]).toMatchObject({ id: 'c-food', parentId: 'c-home', color: '#795548' })
})

test('moving under a main category that has a budget says this budget is deleted', async () => {
  const { user } = await setup((s) => {
    s.put('budgets', { id: 'b-food', categoryId: 'c-food', monthlyLimitCents: 30000, deleted: false })
    s.put('budgets', { id: 'b-home', categoryId: 'c-home', monthlyLimitCents: 90000, deleted: false })
  })
  const dialog = await open(user, 'Lebensmittel')
  await user.selectOptions(dialog.getByLabelText('Gehört zu'), 'Wohnen')
  expect(dialog.getByText('Das Budget dieser Kategorie wird gelöscht, weil Wohnen schon eins hat.')).toBeInTheDocument()
})

test('a new category can be created as a subcategory', async () => {
  const { user, sync } = await setup()
  const dialog = await open(user, 'Neu')
  await user.type(dialog.getByLabelText('Name'), 'Gas')
  await user.selectOptions(dialog.getByLabelText('Gehört zu'), 'Wohnen')
  expect(dialog.queryByText('Farbe')).toBeNull()
  await user.click(dialog.getByRole('button', { name: 'Speichern' }))
  await waitFor(() => expect(pushed(sync)).toHaveLength(1))
  expect(pushed(sync)[0]).toMatchObject({ name: 'Gas', parentId: 'c-home', kind: 'expense', color: '#795548' })
})

test('a subcategory can become a main category again', async () => {
  const { user, sync } = await setup()
  const dialog = await open(user, 'Strom')
  expect(dialog.getByLabelText('Gehört zu')).toHaveValue('c-home')
  await user.selectOptions(dialog.getByLabelText('Gehört zu'), 'Keine (Hauptkategorie)')
  await user.click(dialog.getByRole('button', { name: 'Speichern' }))
  await waitFor(() => expect(pushed(sync)).toHaveLength(1))
  expect(pushed(sync)[0]).toMatchObject({ id: 'c-power', parentId: null })
})
