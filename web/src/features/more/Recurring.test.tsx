import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test } from 'vitest'
import { renderSignedIn } from '../../test/renderApp'
import type { FakeSyncServer } from '../../test/fakeSync'
import { Recurring } from './Recurring'

const category = (id: string, name: string, extra: Record<string, unknown> = {}) => ({
  id, name, icon: 'house', color: '#795548', kind: 'expense', sortOrder: 0, parentId: null, archived: false, deleted: false, ...extra,
})

const rules = (sync: FakeSyncServer) => sync.requests.flatMap((r) => r.changes.recurringRules ?? [])

test('the rule editor offers subcategory chips; a chip only sets the value', async () => {
  const { sync } = await renderSignedIn(<Recurring />, {
    seed: (sync, server) => {
      sync.put('categories', category('c-home', 'Wohnen'))
      sync.put('categories', category('c-power', 'Strom', { parentId: 'c-home' }))
      sync.put('recurringRules', {
        id: 'r1', amountCents: 9000, kind: 'expense', categoryId: 'c-power', paidBy: server.user.id, note: null,
        frequency: 'monthly', interval: 1, startDate: '2026-01-01', endDate: null, deleted: false,
      })
    },
  })
  const user = userEvent.setup()
  await user.click(await screen.findByRole('button', { name: /Wohnen · Strom/ }))
  const dialog = within(await screen.findByRole('dialog'))
  expect(dialog.getByLabelText('Kategorie')).toHaveValue('c-home')
  expect(dialog.queryByRole('option', { name: 'Strom' })).toBeNull()
  const chips = within(dialog.getByRole('group', { name: 'Unterkategorie' }))
  expect(chips.getByRole('button', { name: 'Strom' })).toHaveAttribute('aria-pressed', 'true')

  await user.click(chips.getByRole('button', { name: 'Allgemein' }))
  expect(rules(sync)).toHaveLength(0)
  await user.click(dialog.getByRole('button', { name: 'Speichern' }))
  await waitFor(() => expect(rules(sync)).toHaveLength(1))
  expect(rules(sync)[0]).toMatchObject({ id: 'r1', categoryId: 'c-home' })
})
