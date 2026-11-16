import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { useLocation } from 'react-router'
import { expect, test } from 'vitest'
import { renderSignedIn } from '../../test/renderApp'
import { EntryProvider } from '../quickEntry/EntrySheet'
import { CommandPalette } from './CommandPalette'

function Where() {
  return <p data-testid="where">{useLocation().pathname}</p>
}

async function setup() {
  const ctx = await renderSignedIn(
    <EntryProvider>
      <CommandPalette />
      <Where />
    </EntryProvider>,
    {
      seed: (sync) => {
        sync.put('categories', { id: 'c-food', name: 'Lebensmittel', icon: 'cart', color: '#4CAF50', kind: 'expense', sortOrder: 0, archived: false, deleted: false })
        sync.put('transactions', { id: 't1', amountCents: 1234, kind: 'expense', categoryId: 'c-food', date: '2026-11-02', note: 'Wochenmarkt', paidBy: 'u1', recurringRuleId: null, deleted: false })
      },
    },
  )
  return { ...ctx, user: userEvent.setup() }
}

test('Ctrl+K opens the palette and choosing a page navigates there', async () => {
  const { user } = await setup()
  await user.keyboard('{Control>}k{/Control}')
  await user.type(await screen.findByPlaceholderText(/Suchen/), 'budg')
  await user.click(await screen.findByRole('option', { name: /Budgets/ }))
  await waitFor(() => expect(screen.getByTestId('where')).toHaveTextContent('/budgets'))
  expect(screen.queryByPlaceholderText(/Suchen/)).toBeNull()
})

test('typing finds transactions by note and opens them for editing', async () => {
  const { user } = await setup()
  await user.keyboard('{Control>}k{/Control}')
  await user.type(await screen.findByPlaceholderText(/Suchen/), 'markt')
  await user.click(await screen.findByRole('option', { name: /Wochenmarkt/ }))
  expect(await screen.findByRole('heading', { name: 'Buchung bearbeiten' })).toBeInTheDocument()
})
