import { Download } from 'lucide-react'
import { useMemo, useState } from 'react'
import { useCategoryTree, useData } from '../../app/AppContext'
import { Button } from '../../components/ui/Button'
import { Field, Input } from '../../components/ui/Field'
import { BackLink, PageHeader } from '../../components/ui/Misc'
import { Segmented } from '../../components/ui/Segmented'
import { Tile } from '../../components/ui/Tile'
import { csvBlob, csvFileName, makeCsv } from '../../domain/csv'
import { germanDate, today } from '../../domain/dates'
import { type ExportPeriod, exportRange } from './exportRange'

export function Export() {
  const data = useData()
  const now = today()
  const [period, setPeriod] = useState<ExportPeriod>('thisMonth')
  const [from, setFrom] = useState(`${now.slice(0, 7)}-01`)
  const [to, setTo] = useState(now)
  const tree = useCategoryTree()
  const range = exportRange(period, now, from, to)
  const txs = useMemo(() => [...data.transactions.values()], [data.transactions])
  const count = range ? txs.filter((t) => t.date >= range.from && t.date <= range.to).length : 0

  function download() {
    if (!range) return
    // Names include removed members (iOS exports their names too).
    const url = URL.createObjectURL(csvBlob(makeCsv(txs, tree, data.names, range.from, range.to)))
    const a = document.createElement('a')
    a.href = url
    a.download = csvFileName(range.from, range.to)
    a.click()
    setTimeout(() => URL.revokeObjectURL(url), 1000)
  }

  return (
    <div className="mx-auto max-w-2xl">
      <BackLink />
      <PageHeader title="CSV-Export" subtitle="Excel-kompatibel (Semikolon, Dezimalkomma)" />
      <Tile className="space-y-5">
        <Segmented<ExportPeriod>
          label="Zeitraum"
          value={period}
          onChange={setPeriod}
          options={[
            { value: 'thisMonth', label: 'Monat' },
            { value: 'lastMonth', label: 'Vormonat' },
            { value: 'thisYear', label: 'Jahr' },
            { value: 'custom', label: 'Frei' },
          ]}
        />
        {period === 'custom' && (
          <div className="grid grid-cols-2 gap-3">
            <Field label="Von">{(id) => <Input id={id} type="date" value={from} onChange={(e) => setFrom(e.target.value)} />}</Field>
            <Field label="Bis" error={!range ? 'Bis muss nach Von liegen' : null}>
              {(id) => <Input id={id} type="date" value={to} onChange={(e) => setTo(e.target.value)} />}
            </Field>
          </div>
        )}
        <div className="rounded-2xl bg-tile-2 p-4 text-[14px]">
          {range ? (
            <>
              <div className="font-semibold">
                {germanDate(range.from)} – {germanDate(range.to)}
              </div>
              <div className="text-ink-3">
                {count} {count === 1 ? 'Buchung' : 'Buchungen'} · Spalten: Datum, Art, Kategorie, Betrag, Notiz, Bezahlt von
              </div>
            </>
          ) : (
            <div className="text-ink-3">Kein gültiger Zeitraum</div>
          )}
        </div>
        <Button variant="primary" size="lg" className="w-full" disabled={!range || count === 0} onClick={download}>
          <Download className="size-5" /> Herunterladen
        </Button>
      </Tile>
    </div>
  )
}
