import { CalendarClock, Download, Info, LogOut, Moon, RefreshCw, Shapes, User, Users } from 'lucide-react'
import { useEffect, useState } from 'react'
import { useApp, useData, useMe } from '../../app/AppContext'
import { Button } from '../../components/ui/Button'
import { ConfirmButton } from '../../components/ui/ConfirmButton'
import { Group, ListRow } from '../../components/ui/ListRow'
import { PageHeader } from '../../components/ui/Misc'
import { Segmented } from '../../components/ui/Segmented'
import { type ThemeChoice, useTheme } from '../../lib/theme'

const time = new Intl.DateTimeFormat('de-DE', { hour: '2-digit', minute: '2-digit' })

export function More() {
  const me = useMe()
  const data = useData()
  const { api, store, signOut } = useApp()
  const [theme, setTheme] = useTheme()
  const [syncing, setSyncing] = useState(false)
  // undefined = loading, null = unknown, string = version reported by the server
  const [version, setVersion] = useState<string | null | undefined>(undefined)

  useEffect(() => {
    let cancelled = false
    api
      .health()
      // `|| null` also covers older servers whose /health has no version field
      .then((h) => !cancelled && setVersion(h.version || null))
      .catch(() => !cancelled && setVersion(null))
    return () => {
      cancelled = true
    }
  }, [api])

  const refresh = async () => {
    setSyncing(true)
    await store.pull().catch(() => {})
    setSyncing(false)
  }

  return (
    <div className="mx-auto max-w-2xl">
      <PageHeader title="Mehr" />
      <div className="mb-6 flex items-center gap-4 rounded-tile bg-tile p-5 shadow-tile">
        <span className="grid size-14 place-items-center rounded-[20px] bg-accent-soft text-xl font-semibold text-accent">{me.displayName.slice(0, 1)}</span>
        <div className="min-w-0">
          <div className="truncate text-lg font-semibold tracking-tight">{me.displayName}</div>
          <div className="text-[14px] text-ink-3">
            @{me.username}
            {me.isAdmin && ' · Admin'}
          </div>
        </div>
      </div>

      <div className="space-y-6">
        <Group title="Haushalt">
          <ListRow to="/mehr/kategorien" icon={Shapes} tint="bg-accent-soft text-accent" label="Kategorien" detail={`${[...data.categories.values()].filter((c) => !c.archived).length} aktiv`} />
          <ListRow to="/mehr/wiederkehrend" icon={CalendarClock} tint="bg-pos-soft text-pos" label="Wiederkehrende Buchungen" detail={`${data.recurringRules.size} Regeln`} />
          {me.isAdmin && <ListRow to="/mehr/mitglieder" icon={Users} tint="bg-warn-soft text-warn" label="Mitglieder" detail={`${data.users.size} Personen`} />}
          <ListRow to="/mehr/export" icon={Download} label="CSV-Export" detail="Für Excel und Steuer" />
        </Group>

        <Group title="Konto">
          <ListRow to="/mehr/profil" icon={User} label="Profil und Passwort" />
        </Group>

        <Group title="App">
          <ListRow icon={Moon} label="Darstellung" trailing={<span />} />
          <div className="px-3 pb-3">
            <Segmented<ThemeChoice>
              label="Darstellung"
              value={theme}
              onChange={setTheme}
              options={[
                { value: 'system', label: 'System' },
                { value: 'light', label: 'Hell' },
                { value: 'dark', label: 'Dunkel' },
              ]}
            />
          </div>
          <ListRow
            icon={RefreshCw}
            label={data.online ? 'Mit der NAS verbunden' : 'Keine Verbindung zur NAS'}
            detail={data.lastSyncAt ? `Zuletzt aktualisiert um ${time.format(data.lastSyncAt)} Uhr` : 'Noch nicht synchronisiert'}
            trailing={
              <Button size="sm" onClick={refresh} disabled={syncing}>
                {syncing ? 'Lädt …' : 'Aktualisieren'}
              </Button>
            }
          />
          <ListRow icon={Info} label={version === undefined ? 'Version …' : version ? `Version ${version}` : 'Version unbekannt'} />
        </Group>

        {data.pending > 0 ? (
          <ConfirmButton
            label="Abmelden"
            question={`${data.pending} ${data.pending === 1 ? 'Änderung wird' : 'Änderungen werden'} noch gespeichert. Beim Abmelden gehen sie verloren.`}
            confirmLabel="Trotzdem abmelden"
            onConfirm={() => void signOut()}
          />
        ) : (
          <Button variant="danger" size="lg" className="w-full" onClick={() => void signOut()}>
            <LogOut className="size-5" /> Abmelden
          </Button>
        )}
      </div>
    </div>
  )
}
