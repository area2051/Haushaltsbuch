import { screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test } from 'vitest'
import { today } from '../../domain/dates'
import { renderSignedIn } from '../../test/renderApp'
import { EntryProvider } from '../quickEntry/EntrySheet'
import { Overview } from './Overview'

const category = (id: string, name: string, extra: Record<string, unknown> = {}) => ({
  id, name, icon: 'house', color: '#795548', kind: 'expense', sortOrder: 0, parentId: null, archived: false, deleted: false, ...extra,
})

test('tapping a category with subcategory spending expands its breakdown inline', async () => {
  await renderSignedIn(
    <EntryProvider>
      <Overview />
    </EntryProvider>,
    {
      seed: (sync, server) => {
        sync.put('categories', category('c-home', 'Wohnen'))
        sync.put('categories', category('c-power', 'Strom', { parentId: 'c-home' }))
        sync.put('categories', category('c-food', 'Lebensmittel', { color: '#4CAF50' }))
        const tx = (id: string, categoryId: string, amountCents: number) =>
          sync.put('transactions', { id, amountCents, kind: 'expense', categoryId, date: today(), note: null, paidBy: server.user.id, recurringRuleId: null, deleted: false })
        tx('t1', 'c-home', 10000)
        tx('t2', 'c-power', 6000)
        tx('t3', 'c-food', 4000)
      },
    },
  )
  const user = userEvent.setup()
  const toggle = await screen.findByRole('button', { name: /^Wohnen/, expanded: false })
  // Without subcategory spending there is nothing to expand.
  expect(screen.queryByRole('button', { name: /^Lebensmittel/, expanded: false })).toBeNull()
  expect(screen.queryByRole('list', { name: 'Aufteilung Wohnen' })).toBeNull()

  await user.click(toggle)
  expect(toggle).toHaveAttribute('aria-expanded', 'true')
  const parts = within(screen.getByRole('list', { name: 'Aufteilung Wohnen' })).getAllByRole('listitem')
  expect(parts.map((li) => li.textContent?.replace(/\s/g, ' '))).toEqual([expect.stringMatching(/^Allgemein.*100 €$/), expect.stringMatching(/^Strom.*60 €$/)])

  await user.click(toggle)
  expect(screen.queryByRole('list', { name: 'Aufteilung Wohnen' })).toBeNull()
})
