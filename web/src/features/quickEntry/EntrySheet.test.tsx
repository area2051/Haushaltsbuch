import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test } from 'vitest'
import { today } from '../../domain/dates'
import { renderSignedIn } from '../../test/renderApp'
import type { FakeSyncServer } from '../../test/fakeSync'
import { EntryProvider, useEntry } from './EntrySheet'

function OpenButton() {
  const { openNew } = useEntry()
  return <button onClick={openNew}>öffnen</button>
}

const seedCategories = (sync: FakeSyncServer) => {
  sync.put('categories', { id: 'c-food', name: 'Lebensmittel', icon: 'cart', color: '#4CAF50', kind: 'expense', sortOrder: 0, archived: false, deleted: false })
  sync.put('categories', { id: 'c-pay', name: 'Gehalt', icon: 'banknote', color: '#009688', kind: 'income', sortOrder: 0, archived: false, deleted: false })
}

async function openEntry() {
  const ctx = await renderSignedIn(
    <EntryProvider>
      <OpenButton />
    </EntryProvider>,
    { seed: seedCategories },
  )
  const user = userEvent.setup()
  await user.click(await screen.findByText('öffnen'))
  const dialog = await screen.findByRole('dialog')
  return { ...ctx, user, dialog: within(dialog) }
}

const pushed = (sync: FakeSyncServer) => sync.requests.flatMap((r) => r.changes.transactions ?? [])

test('typing an amount and tapping a category saves an expense for today paid by me', async () => {
  const { user, dialog, sync, server } = await openEntry()
  for (const k of ['1', '2', '5', '0']) await user.click(dialog.getByRole('button', { name: k }))
  expect(dialog.getByLabelText('Betrag')).toHaveTextContent('12,50')

  await user.click(dialog.getByRole('button', { name: /Lebensmittel/ }))
  await waitFor(() => expect(pushed(sync)).toHaveLength(1))
  expect(pushed(sync)[0]).toMatchObject({ amountCents: 1250, kind: 'expense', categoryId: 'c-food', date: today(), paidBy: server.user.id, note: null, deleted: false })
})

test('categories do nothing until an amount is entered', async () => {
  const { user, dialog, sync } = await openEntry()
  await user.click(dialog.getByRole('button', { name: /Lebensmittel/ }))
  expect(pushed(sync)).toHaveLength(0)
})

test('switching to income shows income categories', async () => {
  const { user, dialog } = await openEntry()
  expect(dialog.queryByRole('button', { name: /Gehalt/ })).toBeNull()
  await user.click(dialog.getByRole('radio', { name: 'Einnahme' }))
  expect(dialog.getByRole('button', { name: /Gehalt/ })).toBeInTheDocument()
  expect(dialog.queryByRole('button', { name: /Lebensmittel/ })).toBeNull()
})

test('with details open a category tap only selects; Speichern saves with the note', async () => {
  const { user, dialog, sync } = await openEntry()
  await user.click(dialog.getByRole('button', { name: '5' }))
  await user.click(dialog.getByRole('button', { name: 'Details' }))
  await user.click(dialog.getByRole('button', { name: /Lebensmittel/ }))
  expect(pushed(sync)).toHaveLength(0)

  await user.type(dialog.getByLabelText('Notiz'), 'Bäcker')
  await user.click(dialog.getByRole('button', { name: 'Speichern' }))
  await waitFor(() => expect(pushed(sync)).toHaveLength(1))
  expect(pushed(sync)[0]).toMatchObject({ amountCents: 5, categoryId: 'c-food', note: 'Bäcker' })
})

test('the delete key removes the last digit', async () => {
  const { user, dialog } = await openEntry()
  for (const k of ['4', '2']) await user.click(dialog.getByRole('button', { name: k }))
  await user.click(dialog.getByRole('button', { name: 'Letzte Ziffer löschen' }))
  expect(dialog.getByLabelText('Betrag')).toHaveTextContent('0,04')
})

test('a save that cannot reach the server can be retried from the toast with the same data', async () => {
  const { user, dialog, sync } = await openEntry()
  for (const k of ['7', '5']) await user.click(dialog.getByRole('button', { name: k }))
  sync.offline = true
  await user.click(dialog.getByRole('button', { name: /Lebensmittel/ }))

  const retry = await screen.findByRole('button', { name: 'Erneut versuchen' })
  sync.offline = false
  await user.click(retry)
  await waitFor(() => expect(sync.rows.transactions.size).toBe(1))
  expect([...sync.rows.transactions.values()][0]).toMatchObject({ amountCents: 75, categoryId: 'c-food' })
})

test('while the server is known to be unreachable, categories cannot save', async () => {
  const { user, dialog, sync, store } = await openEntry()
  sync.offline = true
  await store.pull().catch(() => {})
  await user.click(dialog.getByRole('button', { name: '5' }))
  expect(dialog.getByRole('button', { name: /Lebensmittel/ })).toBeDisabled()
  expect(dialog.getByText(/Keine Verbindung/)).toBeInTheDocument()
})
