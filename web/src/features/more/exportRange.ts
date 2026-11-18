import { addMonths, type Day, firstDay, isValidDay, lastDay, monthOf } from '../../domain/dates'

export type ExportPeriod = 'thisMonth' | 'lastMonth' | 'thisYear' | 'custom'
export type Range = { from: Day; to: Day }

/** Range of a CSV export (same presets as iOS); null for an invalid custom range. */
export function exportRange(period: ExportPeriod, today: Day, from = '', to = ''): Range | null {
  const month = monthOf(today)
  switch (period) {
    case 'thisMonth':
      return { from: firstDay(month), to: lastDay(month) }
    case 'lastMonth': {
      const m = addMonths(month, -1)
      return { from: firstDay(m), to: lastDay(m) }
    }
    case 'thisYear':
      return { from: `${today.slice(0, 4)}-01-01`, to: `${today.slice(0, 4)}-12-31` }
    case 'custom':
      return isValidDay(from) && isValidDay(to) && from <= to ? { from, to } : null
  }
}
