import type { components } from '../api/schema'

type S = components['schemas']

export type Kind = 'income' | 'expense'
export type Frequency = 'weekly' | 'monthly' | 'yearly'

export type Category = S['CategoryRecordOut']
export type Transaction = S['TransactionRecordOut']
export type Budget = S['BudgetRecordOut']
export type RecurringRule = S['RecurringRuleRecordOut']
export type Member = S['UserRecord']
export type User = S['UserDto']

export type CategoryInput = S['CategoryRecord']
export type TransactionInput = S['TransactionRecord']
export type BudgetInput = S['BudgetRecord']
export type RecurringRuleInput = S['RecurringRuleRecord']

export type SyncTable = 'categories' | 'transactions' | 'budgets' | 'recurringRules'
export type SyncInput = {
  categories: CategoryInput
  transactions: TransactionInput
  budgets: BudgetInput
  recurringRules: RecurringRuleInput
}
