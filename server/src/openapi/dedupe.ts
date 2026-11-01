type Json = null | boolean | number | string | Json[] | { [k: string]: Json }

function rewriteRefs(value: Json, map: Map<string, string>): Json {
  if (Array.isArray(value)) return value.map((v) => rewriteRefs(v, map))
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([k, v]) => {
        if (k === '$ref' && typeof v === 'string') {
          const name = v.replace('#/components/schemas/', '')
          const target = map.get(name)
          return [k, target ? `#/components/schemas/${target}` : v]
        }
        return [k, rewriteRefs(v, map)]
      }),
    )
  }
  return value
}

/** Zod marks output objects `additionalProperties: false` but not input objects; ignore that when comparing. */
function withoutClosedObjects(value: Json): Json {
  if (Array.isArray(value)) return value.map(withoutClosedObjects)
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value)
        .filter(([k, v]) => !(k === 'additionalProperties' && v === false))
        .map(([k, v]) => [k, withoutClosedObjects(v)]),
    )
  }
  return value
}

/**
 * fastify-type-provider-zod emits every registered schema twice (`Name` for responses,
 * `NameInput` for requests). Where both flavours are identical (always the case for plain JSON
 * shapes), the `NameInput` copy is dropped and all references point at `Name`, so the generated
 * Swift client gets one type per schema.
 */
export function collapseInputSchemas<T extends object>(doc: T): T {
  const components = (doc as { components?: { schemas?: Record<string, unknown> } }).components
  const schemas = (components?.schemas ?? {}) as Record<string, Json>
  let candidates = new Map<string, string>()
  for (const name of Object.keys(schemas)) {
    if (name.endsWith('Input') && name.slice(0, -5) in schemas) candidates.set(name, name.slice(0, -5))
  }
  for (;;) {
    const keep = new Map(
      [...candidates].filter(([input, base]) => {
        const a = JSON.stringify(withoutClosedObjects(rewriteRefs(schemas[input]!, candidates)))
        const b = JSON.stringify(withoutClosedObjects(rewriteRefs(schemas[base]!, candidates)))
        return a === b
      }),
    )
    if (keep.size === candidates.size) break
    candidates = keep
  }
  if (candidates.size === 0) return doc
  return rewriteRefs(
    {
      ...(doc as unknown as Record<string, Json>),
      components: {
        ...(components as unknown as Record<string, Json>),
        schemas: Object.fromEntries(Object.entries(schemas).filter(([name]) => !candidates.has(name))),
      },
    },
    candidates,
  ) as unknown as T
}
