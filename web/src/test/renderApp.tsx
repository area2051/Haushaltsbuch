import { render } from '@testing-library/react'
import type { ReactNode } from 'react'
import { MemoryRouter } from 'react-router'
import { Toaster } from 'sonner'
import { ApiClient } from '../api/client'
import { AppProvider, useApp } from '../app/AppContext'
import { SyncStore } from '../sync/store'
import { FakeServer, memoryTokenStore } from './fakeServer'
import { FakeSyncServer } from './fakeSync'

function WhenReady({ children }: { children: ReactNode }) {
  const { session } = useApp()
  return session.screen === 'ready' ? children : null
}

/**
 * Renders `ui` inside the real app providers, signed in as the fake server's user, with the
 * real ApiClient and SyncStore talking to in-memory fakes. Resolves once the first pull is done.
 */
export async function renderSignedIn(ui: ReactNode, opts: { seed?(sync: FakeSyncServer, server: FakeServer): void; route?: string } = {}) {
  const server = new FakeServer()
  const sync = new FakeSyncServer()
  server.syncHandler = sync.sync as never
  sync.put('users', { ...server.user, deleted: false })
  opts.seed?.(sync, server)
  const { refreshToken } = server.issue()
  const api = new ApiClient({ fetch: server.fetch, tokens: memoryTokenStore(refreshToken), deviceName: 'Test' })
  const store = new SyncStore(api)
  await store.pull()
  const view = render(
    <MemoryRouter initialEntries={[opts.route ?? '/']}>
      <AppProvider deps={{ api, store }}>
        <WhenReady>{ui}</WhenReady>
        <Toaster />
      </AppProvider>
    </MemoryRouter>,
  )
  return { ...view, server, sync, store }
}
