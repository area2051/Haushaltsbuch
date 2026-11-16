import { useCallback } from 'react'
import { toast } from 'sonner'
import { ApiError } from '../api/client'
import { apiErrorText, rejectionText } from '../domain/texts'
import type { SyncInput, SyncTable } from '../domain/types'
import { SaveError } from '../sync/store'
import { useApp } from './AppContext'

export function saveErrorText(e: unknown): string {
  if (e instanceof SaveError) return rejectionText(e.reason)
  return apiErrorText(e instanceof ApiError ? e.code : undefined)
}

type Success<T extends SyncTable> = string | { message: string; description?: string; /** saved when the user taps „Rückgängig“ */ undo?: SyncInput[T] }

/**
 * Saves one record and reports the outcome as a toast. When the server is unreachable the error
 * toast offers „Erneut versuchen“ with the same record, so typed input is not lost.
 * Resolves to true on success.
 */
export function useSaver() {
  const { store } = useApp()
  const save = useCallback(
    async <T extends SyncTable>(table: T, record: SyncInput[T], success?: Success<T>): Promise<boolean> => {
      try {
        await store.save(table, record)
        if (typeof success === 'string') toast.success(success)
        else if (success) {
          const { undo } = success
          toast.success(success.message, {
            description: success.description,
            action: undo ? { label: 'Rückgängig', onClick: () => void save(table, undo) } : undefined,
          })
        }
        return true
      } catch (e) {
        const retryable = e instanceof ApiError && e.code === 'unreachable'
        toast.error('Nicht gespeichert', {
          description: saveErrorText(e),
          duration: retryable ? 15_000 : undefined,
          action: retryable ? { label: 'Erneut versuchen', onClick: () => void save(table, record, success) } : undefined,
        })
        return false
      }
    },
    [store],
  )
  return save
}
