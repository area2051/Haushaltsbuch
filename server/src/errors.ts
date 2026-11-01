import type { FastifyError, FastifyReply, FastifyRequest } from 'fastify'
import { hasZodFastifySchemaValidationErrors } from 'fastify-type-provider-zod'
import { z } from 'zod'

/** Error envelope returned (keep in sync with `envelope()` below) for every non-2xx response. */
export const errorResponse = z
  .object({ error: z.object({ code: z.string(), message: z.string() }) })
  .meta({ id: 'ErrorResponse' })

/** Documents error responses (plus 500) of a route: `response: { 200: x, ...errorResponses(400, 401) }`. */
export function errorResponses<C extends number>(...codes: C[]): Record<C | 500, typeof errorResponse> {
  const out = { 500: errorResponse } as Record<number, typeof errorResponse>
  for (const c of codes) out[c] = errorResponse
  return out as Record<C | 500, typeof errorResponse>
}

export class AppError extends Error {
  constructor(
    public readonly statusCode: number,
    public readonly code: string,
    message: string,
  ) {
    super(message)
    this.name = 'AppError'
  }
}

function envelope(code: string, message: string) {
  return { error: { code, message } }
}

export function errorHandler(err: FastifyError | Error, req: FastifyRequest, reply: FastifyReply) {
  if (err instanceof AppError) {
    return reply.status(err.statusCode).send(envelope(err.code, err.message))
  }
  if (hasZodFastifySchemaValidationErrors(err)) {
    const message = err.validation.map((v) => `${v.instancePath || '/'} ${v.message}`).join('; ')
    return reply.status(400).send(envelope('validation_failed', message))
  }
  const status = (err as FastifyError).statusCode
  if (status && status >= 400 && status < 500) {
    return reply.status(status).send(envelope('bad_request', err.message))
  }
  req.log.error({ err }, 'unhandled error')
  return reply.status(500).send(envelope('internal', 'Internal server error'))
}

export function notFoundHandler(_req: FastifyRequest, reply: FastifyReply) {
  return reply.status(404).send(envelope('not_found', 'Route not found'))
}
