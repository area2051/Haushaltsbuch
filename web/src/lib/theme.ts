import { useEffect, useState } from 'react'
import { safeStorage } from './storage'

export type ThemeChoice = 'system' | 'light' | 'dark'
const KEY = 'hb.theme'

function apply(choice: ThemeChoice) {
  const root = document.documentElement
  if (choice === 'system') root.removeAttribute('data-theme')
  else root.setAttribute('data-theme', choice)
}

export function initTheme(): void {
  apply((safeStorage.get(KEY) as ThemeChoice | null) ?? 'system')
}

export function useTheme(): [ThemeChoice, (t: ThemeChoice) => void] {
  const [choice, setChoice] = useState<ThemeChoice>(() => (safeStorage.get(KEY) as ThemeChoice | null) ?? 'system')
  useEffect(() => {
    apply(choice)
    safeStorage.set(KEY, choice === 'system' ? null : choice)
  }, [choice])
  return [choice, setChoice]
}
