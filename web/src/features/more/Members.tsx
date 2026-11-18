import { Plus, ShieldCheck } from 'lucide-react'
import { type FormEvent, useCallback, useEffect, useState } from 'react'
import { toast } from 'sonner'
import { ApiError, type UserDto } from '../../api/client'
import { useApp, useMe } from '../../app/AppContext'
import { Button } from '../../components/ui/Button'
import { ConfirmButton } from '../../components/ui/ConfirmButton'
import { Field, Input } from '../../components/ui/Field'
import { BackLink, PageHeader, Skeleton } from '../../components/ui/Misc'
import { Sheet } from '../../components/ui/Sheet'
import { DISPLAY_NAME_MAX, passwordProblem, usernameProblem } from '../../domain/accounts'
import { apiErrorText } from '../../domain/texts'

const errText = (e: unknown) => apiErrorText(e instanceof ApiError ? e.code : undefined)

export function Members() {
  const me = useMe()
  const { api, store } = useApp()
  const [users, setUsers] = useState<UserDto[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [editing, setEditing] = useState<UserDto | 'new' | null>(null)

  const load = useCallback(async () => {
    try {
      setUsers((await api.users()).sort((a, b) => a.displayName.localeCompare(b.displayName)))
      setError(null)
    } catch (e) {
      setError(errText(e))
    }
  }, [api])
  useEffect(() => void load(), [load])

  const changed = () => {
    void load()
    void store.pull().catch(() => {})
  }

  if (!me.isAdmin) return <p className="p-6 text-ink-3">Nur für Admins.</p>

  return (
    <div className="mx-auto max-w-2xl">
      <BackLink />
      <PageHeader
        title="Mitglieder"
        subtitle="Alle Konten gehören zu diesem Haushalt"
        actions={
          <Button variant="primary" size="sm" onClick={() => setEditing('new')}>
            <Plus className="size-4" /> Neu
          </Button>
        }
      />
      {error && <p className="mb-4 rounded-2xl bg-warn-soft px-4 py-3 text-[14px] text-warn">{error}</p>}
      {!users ? (
        <Skeleton className="h-40 rounded-tile" />
      ) : (
        <ul className="space-y-2">
          {users.map((u) => (
            <li key={u.id}>
              <button onClick={() => setEditing(u)} className="flex w-full items-center gap-3 rounded-tile bg-tile p-4 text-left shadow-tile">
                <span className="grid size-11 place-items-center rounded-2xl bg-accent-soft font-semibold text-accent">{u.displayName.slice(0, 1)}</span>
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-[15px] font-medium">
                    {u.displayName} {u.id === me.id && <span className="text-ink-3">(du)</span>}
                  </span>
                  <span className="block text-[13px] text-ink-3">@{u.username}</span>
                </span>
                {u.isAdmin && (
                  <span className="inline-flex items-center gap-1 rounded-full bg-tile-2 px-2.5 py-1 text-[12px] font-medium text-ink-2">
                    <ShieldCheck className="size-3.5" /> Admin
                  </span>
                )}
              </button>
            </li>
          ))}
        </ul>
      )}
      <Sheet open={editing !== null} onOpenChange={(o) => !o && setEditing(null)} title={editing === 'new' ? 'Neues Mitglied' : 'Mitglied bearbeiten'}>
        {editing !== null && <MemberForm target={editing} isSelf={editing !== 'new' && editing.id === me.id} onDone={() => setEditing(null)} onChanged={changed} />}
      </Sheet>
    </div>
  )
}

function MemberForm({ target, isSelf, onDone, onChanged }: { target: UserDto | 'new'; isSelf: boolean; onDone(): void; onChanged(): void }) {
  const { api } = useApp()
  const existing = target === 'new' ? null : target
  const [displayName, setDisplayName] = useState(existing?.displayName ?? '')
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [isAdmin, setIsAdmin] = useState(existing?.isAdmin ?? false)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const name = username.trim().toLowerCase()
  const pw = passwordProblem(password, password)

  async function run(action: () => Promise<unknown>, message: string) {
    setBusy(true)
    setError(null)
    try {
      await action()
      toast.success(message)
      onChanged()
      onDone()
    } catch (e) {
      setError(errText(e))
    } finally {
      setBusy(false)
    }
  }

  function submit(e: FormEvent) {
    e.preventDefault()
    if (existing) {
      void run(
        () => api.updateUser(existing.id, { displayName: displayName.trim(), isAdmin, ...(password ? { password } : {}) }),
        password ? 'Gespeichert, Passwort zurückgesetzt' : 'Gespeichert',
      )
    } else {
      void run(() => api.createUser({ username: name, displayName: displayName.trim(), password, isAdmin }), 'Mitglied angelegt')
    }
  }

  const invalid = !displayName.trim() || (existing ? !!password && pw !== null : usernameProblem(name) !== null || pw !== null)

  return (
    <form onSubmit={submit} className="space-y-4">
      <Field label="Anzeigename">{(id) => <Input id={id} value={displayName} maxLength={DISPLAY_NAME_MAX} onChange={(e) => setDisplayName(e.target.value)} />}</Field>
      {!existing && (
        <Field label="Benutzername" error={name && usernameProblem(name) ? '3–32 Zeichen: a–z, 0–9, Punkt, Minus, Unterstrich' : null}>
          {(id) => <Input id={id} autoCapitalize="none" autoCorrect="off" value={username} onChange={(e) => setUsername(e.target.value)} />}
        </Field>
      )}
      <Field label={existing ? 'Neues Passwort (optional)' : 'Passwort'} error={password && pw === 'short' ? 'Mindestens 8 Zeichen' : error}>
        {(id) => <Input id={id} type="password" autoComplete="new-password" value={password} onChange={(e) => setPassword(e.target.value)} />}
      </Field>
      <label className="flex items-center justify-between rounded-2xl bg-tile px-4 py-3 shadow-tile">
        <span className="text-[15px] font-medium">Admin</span>
        <input type="checkbox" role="switch" checked={isAdmin} disabled={isSelf} onChange={(e) => setIsAdmin(e.target.checked)} className="size-5 accent-[var(--ink)]" />
      </label>
      <Button type="submit" variant="primary" size="lg" className="w-full" disabled={busy || invalid}>
        Speichern
      </Button>
      {existing && !isSelf && (
        <ConfirmButton
          label="Mitglied entfernen"
          question={`${existing.displayName} entfernen? Das Konto kann sich nicht mehr anmelden; bisherige Buchungen bleiben erhalten.`}
          confirmLabel="Entfernen"
          disabled={busy}
          onConfirm={() => void run(() => api.updateUser(existing.id, { deleted: true }), `${existing.displayName} entfernt`)}
        />
      )}
    </form>
  )
}
