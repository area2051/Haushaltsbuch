import { expect, test } from 'vitest'
import { apiErrorText, rejectionText } from './texts'

test('known rejection reasons get their own text, unknown ones a generic one', () => {
  const generic = rejectionText('something_new')
  expect(rejectionText('category_in_use')).not.toBe(generic)
  expect(rejectionText(undefined)).toBe(generic)
  // Raw validation messages from the server are never shown.
  expect(rejectionText('amountCents: must be > 0')).toBe(generic)
})

test('known API error codes get their own text, unknown ones a generic one', () => {
  const generic = apiErrorText('something_new')
  for (const code of ['invalid_credentials', 'too_many_attempts', 'username_taken', 'last_admin', 'cannot_delete_self', 'wrong_password', 'unreachable']) {
    expect(apiErrorText(code), code).not.toBe(generic)
  }
})

test('object prototype keys are not treated as known codes', () => {
  expect(rejectionText('constructor')).toBe(rejectionText('something_new'))
  expect(apiErrorText('toString')).toBe(apiErrorText('something_new'))
})

test('the subcategory rejection codes have German texts', () => {
  expect(rejectionText('invalid_parent')).toBe('Diese Zuordnung ist nicht möglich (nur eine Ebene, gleiche Art).')
  expect(rejectionText('category_has_children')).toBe('Die Kategorie hat noch Unterkategorien.')
  expect(rejectionText('budget_on_subcategory')).toBe('Budgets gibt es nur für Hauptkategorien.')
})
