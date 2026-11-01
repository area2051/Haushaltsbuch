import type { FastifyError, FastifyReply, FastifyRequest } from 'fastify'
import { hasZodFastifySchemaValidationErrors } from 'fastify-type-provider-zod'

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
