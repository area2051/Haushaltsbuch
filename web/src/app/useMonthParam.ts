import { useSearchParams } from 'react-router'
import { isValidDay, type Month, monthOf, today } from '../domain/dates'

/** Month from `?monat=YYYY-MM`, defaulting to the current month (which is kept out of the URL). */
export function useMonthParam(): [Month, (m: Month) => void] {
  const [params, setParams] = useSearchParams()
  const current = monthOf(today())
  const raw = params.get('monat')
  const month = raw && isValidDay(`${raw}-01`) ? raw : current
  const setMonth = (m: Month) => setParams(m === current ? {} : { monat: m }, { replace: true })
  return [month, setMonth]
}
