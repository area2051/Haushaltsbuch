import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test, vi } from 'vitest'
import { ConfirmButton } from './ConfirmButton'

test('runs the action only after the second, explicit confirmation', async () => {
  const onConfirm = vi.fn()
  const user = userEvent.setup()
  render(<ConfirmButton label="Mitglied entfernen" question="Ben wirklich entfernen?" confirmLabel="Entfernen" onConfirm={onConfirm} />)

  await user.click(screen.getByRole('button', { name: 'Mitglied entfernen' }))
  expect(onConfirm).not.toHaveBeenCalled()
  expect(await screen.findByText('Ben wirklich entfernen?')).toBeInTheDocument()

  await user.click(screen.getByRole('button', { name: 'Abbrechen' }))
  expect(onConfirm).not.toHaveBeenCalled()

  await user.click(await screen.findByRole('button', { name: 'Mitglied entfernen' }))
  await user.click(await screen.findByRole('button', { name: 'Entfernen' }))
  expect(onConfirm).toHaveBeenCalledOnce()
})
