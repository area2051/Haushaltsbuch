import { screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { renderSignedIn } from '../../test/renderApp'
import { More } from './More'

describe('More: Version', () => {
  it('shows the server version', async () => {
    await renderSignedIn(<More />, {
      seed: (_, s) => {
        s.version = '1.2.3'
      },
    })
    expect(await screen.findByText('Version 1.2.3')).toBeInTheDocument()
  })

  it('shows unknown version when health fails', async () => {
    await renderSignedIn(<More />, {
      seed: (_, s) => {
        const original = s.fetch
        s.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
          if (String(input).endsWith('/health')) throw new TypeError('Failed to fetch')
          return original(input, init)
        }) as typeof s.fetch
      },
    })
    expect(await screen.findByText('Version unbekannt')).toBeInTheDocument()
  })

  it('shows unknown version when /health answers without a version field', async () => {
    await renderSignedIn(<More />, {
      seed: (_, s) => {
        // Older server during an update: undefined is dropped by JSON serialisation.
        s.version = undefined as unknown as string
      },
    })
    expect(await screen.findByText('Version unbekannt')).toBeInTheDocument()
  })
})
