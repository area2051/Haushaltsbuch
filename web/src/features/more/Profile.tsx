import { type FormEvent, useState } from 'react'
import { toast } from 'sonner'
import { ApiError } from '../../api/client'
import { useApp, useMe } from '../../app/AppContext'
import { Button } from '../../components/ui/Button'
import { Field, Input } from '../../components/ui/Field'
import { BackLink, PageHeader } from '../../components/ui/Misc'
import { Tile, TileLabel } from '../../components/ui/Tile'
import { DISPLAY_NAME_MAX, passwordProblem } from '../../domain/accounts'
import { apiErrorText } from '../../domain/texts'

const errText = (e: unknown) => apiErrorText(e instanceof ApiError ? e.code : undefined)

export function Profile() {
  const me = useMe()
  const { api, store, setUser } = useApp()
  const [name, setName] = useState(me.displayName)
  const [current, setCurrent] = useState('')
  const [next, setNext] = useState('')
  const [confirm, setConfirm] = useState('')
  const [busy, setBusy] = useState(false)
  const [pwError, setPwError] = useState<string | null>(null)
  const pwProblem = passwordProblem(next, confirm)

  async function saveName(e: FormEvent) {
    e.preventDefault()
    setBusy(true)
    try {
      setUser(await api.updateMe({ displayName: name.trim() }))
      void store.pull().catch(() => {})
      toast.success('Name gespeichert')
    } catch (err) {
      toast.error('Nicht gespeichert', { description: errText(err) })
    } finally {
      setBusy(false)
    }
  }

  async function savePassword(e: FormEvent) {
    e.preventDefault()
    if (pwProblem || !current) return
    setBusy(true)
    setPwError(null)
    try {
      await api.updateMe({ currentPassword: current, newPassword: next })
      setCurrent('')
      setNext('')
      setConfirm('')
      toast.success('Passwort geändert', { description: 'Andere Geräte müssen sich neu anmelden.' })
    } catch (err) {
      setPwError(errText(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <BackLink />
      <PageHeader title="Profil" subtitle={`@${me.username}`} />
      <Tile>
        <form onSubmit={saveName} className="space-y-4">
          <TileLabel>Anzeigename</TileLabel>
          <Field label="Name">{(id) => <Input id={id} value={name} maxLength={DISPLAY_NAME_MAX} onChange={(e) => setName(e.target.value)} />}</Field>
          <Button type="submit" variant="primary" disabled={busy || !name.trim() || name.trim() === me.displayName}>
            Speichern
          </Button>
        </form>
      </Tile>
      <Tile>
        <form onSubmit={savePassword} className="space-y-4">
          <TileLabel>Passwort ändern</TileLabel>
          <Field label="Aktuelles Passwort">{(id) => <Input id={id} type="password" autoComplete="current-password" value={current} onChange={(e) => setCurrent(e.target.value)} />}</Field>
          <Field label="Neues Passwort" error={next && pwProblem === 'short' ? 'Mindestens 8 Zeichen' : null}>
            {(id) => <Input id={id} type="password" autoComplete="new-password" value={next} onChange={(e) => setNext(e.target.value)} />}
          </Field>
          <Field label="Neues Passwort wiederholen" error={confirm && pwProblem === 'mismatch' ? 'Passwörter stimmen nicht überein' : pwError}>
            {(id) => <Input id={id} type="password" autoComplete="new-password" value={confirm} onChange={(e) => setConfirm(e.target.value)} />}
          </Field>
          <Button type="submit" variant="primary" disabled={busy || !current || !!pwProblem}>
            Passwort ändern
          </Button>
        </form>
      </Tile>
    </div>
  )
}
