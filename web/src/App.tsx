import { Toaster } from 'sonner'
import { BrowserRouter, Route, Routes } from 'react-router'
import { AppProvider, useApp } from './app/AppContext'
import { Shell } from './app/Shell'
import { Login, Setup, Unreachable } from './features/onboarding/Onboarding'
import { Overview } from './features/overview/Overview'
import { Budgets } from './features/budgets/Budgets'
import { Categories } from './features/more/Categories'
import { Export } from './features/more/Export'
import { Members } from './features/more/Members'
import { More } from './features/more/More'
import { Profile } from './features/more/Profile'
import { Recurring } from './features/more/Recurring'
import { Transactions } from './features/transactions/Transactions'

function Screens() {
  const { session } = useApp()
  switch (session.screen) {
    case 'checking':
      return <div className="grid min-h-dvh place-items-center"><img src="/app/icon.svg" alt="Lädt" className="size-12 animate-pulse rounded-2xl" /></div>
    case 'setup':
      return <Setup />
    case 'login':
      return <Login />
    case 'unreachable':
      return <Unreachable />
    case 'ready':
      return (
        <Routes>
          <Route element={<Shell />}>
            <Route index element={<Overview />} />
            <Route path="buchungen" element={<Transactions />} />
            <Route path="budgets" element={<Budgets />} />
            <Route path="mehr" element={<More />} />
            <Route path="mehr/kategorien" element={<Categories />} />
            <Route path="mehr/wiederkehrend" element={<Recurring />} />
            <Route path="mehr/export" element={<Export />} />
            <Route path="mehr/profil" element={<Profile />} />
            <Route path="mehr/mitglieder" element={<Members />} />
            <Route path="*" element={<Overview />} />
          </Route>
        </Routes>
      )
  }
}

export function App() {
  return (
    <BrowserRouter basename="/app">
      <AppProvider>
        <Screens />
        <Toaster position="top-center" offset={16} toastOptions={{ className: '!rounded-2xl !bg-tile !text-ink !border-0 !shadow-float !font-sans' }} />
      </AppProvider>
    </BrowserRouter>
  )
}
