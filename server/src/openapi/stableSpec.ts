/** Recursively sorts object keys so the serialized spec is deterministic. Array order is kept. */
function sortKeys(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortKeys)
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
        .map(([k, v]) => [k, sortKeys(v)]),
    )
  }
  return value
}

/** Normalizes a swagger document: plain JSON (no undefined) with sorted keys. */
export function stableSpec(doc: unknown): unknown {
  return sortKeys(JSON.parse(JSON.stringify(doc)))
}

export function serializeSpec(doc: unknown): string {
  return JSON.stringify(stableSpec(doc), null, 2) + '\n'
}
