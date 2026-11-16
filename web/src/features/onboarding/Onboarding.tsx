import { ArrowRight, WifiOff } from 'lucide-react'
import { motion } from 'motion/react'
import { type FormEvent, useState } from 'react'
import { ApiError } from '../../api/client'
import { useApp } from '../../app/AppContext'
import { Button } from '../../components/ui/Button'
import { Field, Input } from '../../components/ui/Field'
import { DISPLAY_NAME_MAX, usernameProblem } from '../../domain/accounts'
import { apiErrorText } from '../../domain/texts'

function Frame({ title, text, children }: { title: string; text: string; children: React.ReactNode }) {
  return (
    <div className="flex min-h-dvh items-center justify-center px-5 py-10 pt-safe">
      <motion.div
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4, ease: [0.22, 1, 0.36, 1] }}
        className="w-full max-w-sm"
      >
        <img src="/app/icon.svg" alt="" className="mb-8 size-14 rounded-[18px] shadow-tile" />
        <h1 className="text-[32px] font-semibold leading-tight tracking-[-0.03em]">{title}</h1>
        <p className="mb-8 mt-2 text-[15px] text-ink-3">{text}</p>
        {children}
      </motion.div>
    </div>
  )
}

export function Login() {
  const { api, signedIn } = useApp()
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  async function submit(e: FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError(null)
    try {
      signedIn(await api.login(username.trim(), password))
    } catch (err) {
      setError(apiErrorText(err instanceof ApiError ? err.code : undefined))
    } finally {
      setBusy(false)
    }
  }

  return (
    <Frame title="Willkommen zurück" text="Melde dich mit deinem Haushaltsbuch-Konto an.">
      <form onSubmit={submit} className="space-y-4">
        <Field label="Benutzername">
          {(id) => <Input id={id} autoComplete="username" autoCapitalize="none" autoCorrect="off" value={username} onChange={(e) => setUsername(e.target.value)} required />}
        </Field>
        <Field label="Passwort" error={error}>
          {(id) => <Input id={id} type="password" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} required />}
        </Field>
        <Button type="submit" variant="primary" size="lg" className="mt-2 w-full" disabled={busy || !username || !password}>
          Anmelden <ArrowRight className="size-5" />
        </Button>
      </form>
    </Frame>
  )
}

export function Setup() {
  const { api, signedIn } = useApp()
  const [displayName, setDisplayName] = useState('')
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const name = username.trim().toLowerCase()
  const usernameError = usernameProblem(name) === 'format' ? '3–32 Zeichen: Kleinbuchstaben, Ziffern, Punkt, Minus, Unterstrich.' : null
  const passwordError = password && password.length < 8 ? 'Mindestens 8 Zeichen.' : null

  async function submit(e: FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError(null)
    try {
      await api.setup({ username: name, displayName: displayName.trim(), password })
      signedIn(await api.login(name, password))
    } catch (err) {
      setError(apiErrorText(err instanceof ApiError ? err.code : undefined))
    } finally {
      setBusy(false)
    }
  }

  return (
    <Frame title="Haushaltsbuch einrichten" text="Lege das erste Konto an. Es wird Admin und kann weitere Mitglieder hinzufügen.">
      <form onSubmit={submit} className="space-y-4">
        <Field label="Anzeigename">{(id) => <Input id={id} value={displayName} onChange={(e) => setDisplayName(e.target.value)} maxLength={DISPLAY_NAME_MAX} required />}</Field>
        <Field label="Benutzername" error={usernameError}>
          {(id) => <Input id={id} autoComplete="username" autoCapitalize="none" value={username} onChange={(e) => setUsername(e.target.value)} required />}
        </Field>
        <Field label="Passwort" error={passwordError ?? error}>
          {(id) => <Input id={id} type="password" autoComplete="new-password" value={password} onChange={(e) => setPassword(e.target.value)} required />}
        </Field>
        <Button
          type="submit"
          variant="primary"
          size="lg"
          className="mt-2 w-full"
          disabled={busy || !displayName.trim() || !name || !!usernameError || password.length < 8}
        >
          Einrichten <ArrowRight className="size-5" />
        </Button>
      </form>
    </Frame>
  )
}

export function Unreachable() {
  const { retry } = useApp()
  return (
    <Frame title="Server nicht erreichbar" text="Bist du im Heimnetz oder per VPN verbunden? Das Haushaltsbuch läuft auf deiner NAS.">
      <div className="mb-6 grid size-14 place-items-center rounded-[20px] bg-warn-soft text-warn">
        <WifiOff className="size-6" />
      </div>
      <Button variant="primary" size="lg" className="w-full" onClick={retry}>
        Erneut versuchen
      </Button>
    </Frame>
  )
}
