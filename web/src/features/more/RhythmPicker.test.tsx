import { fireEvent, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { useState } from 'react'
import { expect, test } from 'vitest'
import { type Rhythm, RhythmPicker } from './RhythmPicker'

function Harness({ initial, allowNone }: { initial: Rhythm | null; allowNone?: boolean }) {
  const [v, setV] = useState<Rhythm | null>(initial)
  return (
    <>
      <RhythmPicker value={v} onChange={setV} allowNone={allowNone} />
      <output data-testid="v">{v ? `${v.frequency}×${v.interval}` : 'none'}</output>
    </>
  )
}

const value = () => screen.getByTestId('v').textContent

test('choosing a preset sets unit and interval', async () => {
  render(<Harness initial={{ frequency: 'monthly', interval: 1 }} />)
  await userEvent.selectOptions(screen.getByLabelText('Rhythmus'), 'Vierteljährlich')
  expect(value()).toBe('monthly×3')
  expect(screen.queryByLabelText('Anzahl Monate')).toBeNull()
})

test('"Alle N Monate" shows a number field', async () => {
  render(<Harness initial={{ frequency: 'monthly', interval: 1 }} />)
  await userEvent.selectOptions(screen.getByLabelText('Rhythmus'), 'Alle N Monate …')
  const n = screen.getByLabelText('Anzahl Monate')
  fireEvent.change(n, { target: { value: '4' } })
  expect(value()).toBe('monthly×4')
})

test('a stored custom rhythm opens as custom with its number', () => {
  render(<Harness initial={{ frequency: 'monthly', interval: 5 }} />)
  expect(screen.getByLabelText('Anzahl Monate')).toHaveValue(5)
})

test('with allowNone, "Nicht wiederholen" clears the rhythm', async () => {
  render(<Harness initial={null} allowNone />)
  expect(value()).toBe('none')
  await userEvent.selectOptions(screen.getByLabelText('Wiederholen'), 'Monatlich')
  expect(value()).toBe('monthly×1')
  await userEvent.selectOptions(screen.getByLabelText('Wiederholen'), 'Nicht wiederholen')
  expect(value()).toBe('none')
})

test('typing a number that matches a preset keeps the custom field open', async () => {
  render(<Harness initial={{ frequency: 'monthly', interval: 1 }} />)
  await userEvent.selectOptions(screen.getByLabelText('Rhythmus'), 'Alle N Monate …')
  const n = screen.getByLabelText('Anzahl Monate')
  await userEvent.clear(n)
  await userEvent.type(n, '12')
  expect(value()).toBe('monthly×12')
  expect(screen.getByLabelText('Anzahl Monate')).toBeInTheDocument()
})

test('a stored custom weekly rhythm is offered as "Alle N Wochen"', () => {
  render(<Harness initial={{ frequency: 'weekly', interval: 3 }} />)
  expect(screen.getByLabelText('Rhythmus')).toHaveDisplayValue('Alle N Wochen …')
  expect(screen.getByLabelText('Anzahl Wochen')).toHaveValue(3)
})
