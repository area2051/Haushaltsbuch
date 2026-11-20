import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { useState } from 'react'
import { expect, test, vi } from 'vitest'
import { categoryTree } from '../domain/categoryTree'
import { cat } from '../test/fixtures'
import { SubcategoryChips } from './SubcategoryChips'

const tree = categoryTree([
  cat('home', 'expense', { name: 'Wohnen' }),
  cat('power', 'expense', { name: 'Strom', parentId: 'home', sortOrder: 0 }),
  cat('gas', 'expense', { name: 'Gas', parentId: 'home', sortOrder: 1, archived: true }),
  cat('tax', 'expense', { name: 'Grundsteuer', parentId: 'home', sortOrder: 2 }),
  cat('food', 'expense', { name: 'Lebensmittel' }),
])

function Harness({ onChange }: { onChange(id: string): void }) {
  const [value, setValue] = useState('home')
  return (
    <SubcategoryChips
      parentId="home"
      value={value}
      tree={tree}
      onChange={(id) => {
        setValue(id)
        onChange(id)
      }}
    />
  )
}

test('"Allgemein" (the main category itself) is preselected, followed by the selectable children', () => {
  render(<Harness onChange={() => {}} />)
  const chips = screen.getAllByRole('button')
  expect(chips.map((c) => c.textContent)).toEqual(['Allgemein', 'Strom', 'Grundsteuer'])
  expect(screen.getByRole('button', { name: 'Allgemein' })).toHaveAttribute('aria-pressed', 'true')
  expect(screen.getByRole('button', { name: 'Strom' })).toHaveAttribute('aria-pressed', 'false')
})

test('clicking a chip selects that subcategory', async () => {
  const onChange = vi.fn()
  render(<Harness onChange={onChange} />)
  await userEvent.click(screen.getByRole('button', { name: 'Strom' }))
  expect(onChange).toHaveBeenLastCalledWith('power')
  expect(screen.getByRole('button', { name: 'Strom' })).toHaveAttribute('aria-pressed', 'true')
  await userEvent.click(screen.getByRole('button', { name: 'Allgemein' }))
  expect(onChange).toHaveBeenLastCalledWith('home')
})

test('an archived child is not offered', () => {
  render(<Harness onChange={() => {}} />)
  expect(screen.queryByRole('button', { name: 'Gas' })).toBeNull()
})

test('renders nothing for a category without selectable children', () => {
  const { container } = render(<SubcategoryChips parentId="food" value="food" tree={tree} onChange={() => {}} />)
  expect(container).toBeEmptyDOMElement()
})
