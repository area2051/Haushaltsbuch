import { fireEvent, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test } from 'vitest'
import { useData } from '../../app/AppContext'
import { today } from '../../domain/dates'
import { renderSignedIn } from '../../test/renderApp'
import type { FakeSyncServer } from '../../test/fakeSync'
import { EntryProvider, useEntry } from './EntrySheet'

function OpenButton() {
  const { openNew, openEdit } = useEntry()
  const data = useData()
  const powerTx = data.transactions.get('t-power')
  return (
    <>
      <button onClick={openNew}>öffnen</button>
      {powerTx && <button onClick={() => openEdit(powerTx)}>Strombuchung bearbeiten</button>}
    </>
  )
}

const seedCategories = (sync: FakeSyncServer) => {
  sync.put('categories', { id: 'c-food', name: 'Lebensmittel', icon: 'cart', color: '#4CAF50', kind: 'expense', sortOrder: 0, archived: false, deleted: false })
  sync.put('categories', { id: 'c-pay', name: 'Gehalt', icon: 'banknote', color: '#009688', kind: 'income', sortOrder: 0, archived: false, deleted: false })
  sync.put('categories', { id: 'c-home', name: 'Wohnen', icon: 'house', color: '#795548', kind: 'expense', sortOrder: 1, parentId: null, archived: false, deleted: false })
  sync.put('categories', { id: 'c-power', name: 'Strom', icon: 'bolt', color: '#795548', kind: 'expense', sortOrder: 0, parentId: 'c-home', archived: false, deleted: false })
  sync.put('categories', { id: 'c-gas', name: 'Gas', icon: 'flame', color: '#795548', kind: 'expense', sortOrder: 1, parentId: 'c-home', archived: true, deleted: false })
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

test('with "Wiederholen" set, saving creates a rule from the chosen date instead of a single booking', async () => {
  const { user, dialog, sync, server } = await openEntry()
  for (const k of ['8', '9', '0', '0']) await user.click(dialog.getByRole('button', { name: k }))
  await user.click(dialog.getByRole('button', { name: 'Details' }))
  await user.selectOptions(dialog.getByLabelText('Wiederholen'), 'Vierteljährlich')
  await user.click(dialog.getByRole('button', { name: /Lebensmittel/ }))
  await user.type(dialog.getByLabelText('Notiz'), 'Grundsteuer')
  await user.click(dialog.getByRole('button', { name: 'Speichern' }))

  await waitFor(() => expect(sync.requests.flatMap((r) => r.changes.recurringRules ?? [])).toHaveLength(1))
  expect(sync.requests.flatMap((r) => r.changes.recurringRules ?? [])[0]).toMatchObject({
    amountCents: 8900,
    kind: 'expense',
    categoryId: 'c-food',
    note: 'Grundsteuer',
    paidBy: server.user.id,
    frequency: 'monthly',
    interval: 3,
    startDate: today(),
    endDate: null,
    deleted: false,
  })
  expect(pushed(sync)).toHaveLength(0)
})

test('collapsing Details clears "Wiederholen", so a category tap books once', async () => {
  const { user, dialog, sync } = await openEntry()
  await user.click(dialog.getByRole('button', { name: '5' }))
  await user.click(dialog.getByRole('button', { name: 'Details' }))
  await user.selectOptions(dialog.getByLabelText('Wiederholen'), 'Monatlich')
  await user.click(dialog.getByRole('button', { name: 'Details' }))
  await user.click(dialog.getByRole('button', { name: /Lebensmittel/ }))
  await waitFor(() => expect(pushed(sync)).toHaveLength(1))
  expect(sync.requests.flatMap((r) => r.changes.recurringRules ?? [])).toHaveLength(0)
})

test('an invalid repeat (date before 2000) disables Speichern instead of silently doing nothing', async () => {
  const { user, dialog } = await openEntry()
  await user.click(dialog.getByRole('button', { name: '5' }))
  await user.click(dialog.getByRole('button', { name: 'Details' }))
  await user.click(dialog.getByRole('button', { name: /Lebensmittel/ }))
  await user.selectOptions(dialog.getByLabelText('Wiederholen'), 'Monatlich')
  fireEvent.change(dialog.getByLabelText('Datum'), { target: { value: '1999-12-01' } })
  expect(dialog.getByRole('button', { name: 'Speichern' })).toBeDisabled()
})

const chips = (dialog: ReturnType<typeof within>) => within(dialog.getByRole('group', { name: 'Unterkategorie' }))

test('books on a subcategory: tapping a main category with children shows the chips, a chip tap saves', async () => {
  const { user, dialog, sync } = await openEntry()
  expect(dialog.queryByRole('button', { name: /Strom/ })).toBeNull()
  for (const k of ['4', '2']) await user.click(dialog.getByRole('button', { name: k }))
  await user.click(dialog.getByRole('button', { name: /Wohnen/ }))
  expect(pushed(sync)).toHaveLength(0)
  expect(chips(dialog).getByRole('button', { name: 'Allgemein' })).toHaveAttribute('aria-pressed', 'true')
  expect(chips(dialog).queryByRole('button', { name: 'Gas' })).toBeNull()

  await user.click(chips(dialog).getByRole('button', { name: 'Strom' }))
  await waitFor(() => expect(pushed(sync)).toHaveLength(1))
  expect(pushed(sync)[0]).toMatchObject({ amountCents: 42, categoryId: 'c-power' })
})

test('in the fast path the "Allgemein" chip books on the main category', async () => {
  const { user, dialog, sync } = await openEntry()
  await user.click(dialog.getByRole('button', { name: '9' }))
  await user.click(dialog.getByRole('button', { name: /Wohnen/ }))
  await user.click(chips(dialog).getByRole('button', { name: 'Allgemein' }))
  await waitFor(() => expect(pushed(sync)).toHaveLength(1))
  expect(pushed(sync)[0]).toMatchObject({ amountCents: 9, categoryId: 'c-home' })
})

test('with details open chips only select; switching the main category resets to "Allgemein"', async () => {
  const { user, dialog, sync } = await openEntry()
  await user.click(dialog.getByRole('button', { name: '5' }))
  await user.click(dialog.getByRole('button', { name: 'Details' }))
  await user.click(dialog.getByRole('button', { name: /Wohnen/ }))
  await user.click(chips(dialog).getByRole('button', { name: 'Strom' }))
  expect(pushed(sync)).toHaveLength(0)
  expect(chips(dialog).getByRole('button', { name: 'Strom' })).toHaveAttribute('aria-pressed', 'true')

  await user.click(dialog.getByRole('button', { name: /Lebensmittel/ }))
  expect(dialog.queryByRole('group', { name: 'Unterkategorie' })).toBeNull()
  await user.click(dialog.getByRole('button', { name: /Wohnen/ }))
  expect(chips(dialog).getByRole('button', { name: 'Allgemein' })).toHaveAttribute('aria-pressed', 'true')

  await user.click(chips(dialog).getByRole('button', { name: 'Strom' }))
  await user.click(dialog.getByRole('button', { name: 'Speichern' }))
  await waitFor(() => expect(pushed(sync)).toHaveLength(1))
  expect(pushed(sync)[0]).toMatchObject({ amountCents: 5, categoryId: 'c-power' })
})

test('editing a subcategory booking preselects the main category and the subcategory chip', async () => {
  const ctx = await renderSignedIn(
    <EntryProvider>
      <OpenButton />
    </EntryProvider>,
    {
      seed: (sync) => {
        seedCategories(sync)
        sync.put('transactions', { id: 't-power', amountCents: 6000, kind: 'expense', categoryId: 'c-power', date: '2026-11-02', note: null, paidBy: 'u1', recurringRuleId: null, deleted: false })
      },
    },
  )
  const user = userEvent.setup()
  await user.click(await screen.findByText('Strombuchung bearbeiten'))
  const dialog = within(await screen.findByRole('dialog'))
  expect(dialog.getByRole('button', { name: /Wohnen/ })).toHaveAttribute('aria-pressed', 'true')
  expect(chips(dialog).getByRole('button', { name: 'Strom' })).toHaveAttribute('aria-pressed', 'true')

  await user.click(chips(dialog).getByRole('button', { name: 'Allgemein' }))
  expect(pushed(ctx.sync)).toHaveLength(0)
  await user.click(dialog.getByRole('button', { name: 'Speichern' }))
  await waitFor(() => expect(pushed(ctx.sync)).toHaveLength(1))
  expect(pushed(ctx.sync)[0]).toMatchObject({ id: 't-power', categoryId: 'c-home' })
})
