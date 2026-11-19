import { useId, useState } from 'react'
import { Input, Select } from '../../components/ui/Field'
import type { Frequency } from '../../domain/types'
import { MAX_INTERVAL, presetFor, RHYTHM_PRESETS } from './rules'

export type Rhythm = { frequency: Frequency; interval: number }

const UNIT: Record<Frequency, string> = { weekly: 'Wochen', monthly: 'Monate', yearly: 'Jahre' }
const NONE = 'none'
const CUSTOM = 'custom'

/**
 * Select box with the common rhythms plus „Alle N Monate …“ (number field). With `allowNone`
 * the first option is „Nicht wiederholen“ (value null), used by the entry sheet.
 */
export function RhythmPicker({ value, onChange, allowNone }: { value: Rhythm | null; onChange(r: Rhythm | null): void; allowNone?: boolean }) {
  const id = useId()
  // Own state: otherwise typing „12“ would hit the preset „Monatlich“ at „1“ and close the field.
  const [customMode, setCustomMode] = useState(() => value !== null && presetFor(value.frequency, value.interval) === CUSTOM)
  const selected = value === null ? NONE : customMode ? CUSTOM : presetFor(value.frequency, value.interval)
  // Text state so the number field can be empty while typing.
  const [text, setText] = useState(value ? String(value.interval) : '2')

  function choose(v: string) {
    if (v === NONE) {
      setCustomMode(false)
      return onChange(null)
    }
    if (v === CUSTOM) {
      const n = value && selected === CUSTOM ? value.interval : 2
      setCustomMode(true)
      setText(String(n))
      return onChange({ frequency: value && selected === CUSTOM ? value.frequency : 'monthly', interval: n })
    }
    setCustomMode(false)
    const p = RHYTHM_PRESETS.find((x) => x.id === v)!
    onChange({ frequency: p.frequency, interval: p.interval })
  }

  return (
    <div className="space-y-2">
      <label htmlFor={id} className="block px-1 text-[13px] font-medium text-ink-2">
        {allowNone ? 'Wiederholen' : 'Rhythmus'}
      </label>
      <Select id={id} value={selected} onChange={(e) => choose(e.target.value)}>
        {allowNone && <option value={NONE}>Nicht wiederholen</option>}
        {RHYTHM_PRESETS.map((p) => (
          <option key={p.id} value={p.id}>
            {p.label}
          </option>
        ))}
        <option value={CUSTOM}>{`Alle N ${UNIT[value && selected === CUSTOM ? value.frequency : 'monthly']} …`}</option>
      </Select>
      {value && selected === CUSTOM && (
        <div className="flex items-center gap-3 px-1">
          <span className="text-[15px] text-ink-2">Alle</span>
          <Input
            type="number"
            inputMode="numeric"
            min={1}
            max={MAX_INTERVAL}
            aria-label={`Anzahl ${UNIT[value.frequency]}`}
            value={text}
            onChange={(e) => {
              setText(e.target.value)
              onChange({ frequency: value.frequency, interval: Number(e.target.value) || 0 })
            }}
            className="num w-24 text-center"
          />
          <span className="text-[15px] text-ink-2">{UNIT[value.frequency]}</span>
        </div>
      )}
    </div>
  )
}
