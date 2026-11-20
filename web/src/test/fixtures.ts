import type { Budget, Category, Kind, Transaction } from '../domain/types'

let n = 0
const uuid = () => `00000000-0000-4000-8000-${String(++n).padStart(12, '0')}`

export function tx(
  amountCents: number,
  date: string,
  opts: Partial<Omit<Transaction, 'amountCents' | 'date'>> = {},
): Transaction {
  return {
    id: uuid(),
    amountCents,
    date,
    kind: 'expense',
    categoryId: 'cat-a',
    paidBy: 'user-1',
    note: null,
    recurringRuleId: null,
    deleted: false,
    version: 1,
    ...opts,
  }
}

export function cat(id: string, kind: Kind = 'expense', opts: Partial<Category> = {}): Category {
  return { id, name: id, icon: 'cart', color: '#4CAF50', kind, sortOrder: 0, parentId: null, archived: false, deleted: false, version: 1, ...opts }
}

export function budget(categoryId: string, monthlyLimitCents: number): Budget {
  return { id: uuid(), categoryId, monthlyLimitCents, deleted: false, version: 1 }
}
