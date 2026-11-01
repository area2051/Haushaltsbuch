export type DefaultCategory = {
  name: string
  icon: string
  color: string
  kind: 'income' | 'expense'
}

export const DEFAULT_CATEGORIES: ReadonlyArray<DefaultCategory> = [
  { name: 'Lebensmittel', icon: 'cart', color: '#4CAF50', kind: 'expense' },
  { name: 'Wohnen', icon: 'house', color: '#795548', kind: 'expense' },
  { name: 'Mobilität', icon: 'car', color: '#2196F3', kind: 'expense' },
  { name: 'Freizeit', icon: 'gamecontroller', color: '#9C27B0', kind: 'expense' },
  { name: 'Gesundheit', icon: 'cross.case', color: '#F44336', kind: 'expense' },
  { name: 'Kleidung', icon: 'tshirt', color: '#E91E63', kind: 'expense' },
  { name: 'Abos', icon: 'repeat', color: '#FF9800', kind: 'expense' },
  { name: 'Sonstiges', icon: 'ellipsis.circle', color: '#607D8B', kind: 'expense' },
  { name: 'Gehalt', icon: 'banknote', color: '#009688', kind: 'income' },
  { name: 'Sonstige Einnahmen', icon: 'plus.circle', color: '#8BC34A', kind: 'income' },
]
