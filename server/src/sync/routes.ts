import type { FastifyInstance } from 'fastify'
import { validatorCompiler, type ZodTypeProvider } from 'fastify-type-provider-zod'
import type { z } from 'zod'
import { todayIn } from '../clock.js'
import { syncRequest, type SyncRequest, syncRequestEnvelope, syncResponse } from './schemas.js'
import { applySync, pullLocked } from './service.js'

export type SyncRoutesOptions = {
  /** Called after a sync that changed recurring rules (Task 8: generate due transactions). */
  onRulesChanged?: () => Promise<void>
}

export async function syncRoutes(app: FastifyInstance, opts: SyncRoutesOptions): Promise<void> {
  const r = app.withTypeProvider<ZodTypeProvider>()

  r.post(
    '/sync',
    {
      onRequest: app.authenticate,
      // `body` is the fully typed SyncRequest so OpenAPI documents typed record arrays...
      schema: { body: syncRequest, response: { 200: syncResponse } },
      // ...but validation only checks the envelope; records are parsed one by one in applySync
      // so a single invalid record is rejected alone (spec §4).
      validatorCompiler: (route) =>
        validatorCompiler({
          ...route,
          schema: route.httpPart === 'body' ? syncRequestEnvelope : (route.schema as unknown as z.ZodType),
        }),
    },
    async (req) => {
      const body = req.body as unknown as SyncRequest
      const today = todayIn(app.clock, app.config.timeZone)
      const { response, rulesChanged } = await applySync(app.db, req.user.id, body, today)
      if (!rulesChanged || !opts.onRulesChanged) return response

      try {
        await opts.onRulesChanged()
      } catch (err) {
        // The push is already committed; the daily scheduler catches up on generation.
        req.log.error({ err }, 'onRulesChanged failed after sync')
        return response
      }
      // Re-pull so records written by the hook are part of this response.
      const pulled = await pullLocked(app.db, response.fullResync ? 0 : body.lastVersion)
      return { ...response, ...pulled }
    },
  )
}
