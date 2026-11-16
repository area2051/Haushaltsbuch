const randomBytes = () => crypto.getRandomValues(new Uint8Array(16))

/**
 * Random UUID v4. `crypto.randomUUID` only exists in secure contexts, but the app is usually
 * opened via plain http on the LAN; `getRandomValues` works everywhere.
 */
export function uuidv4(random: () => Uint8Array = randomBytes): string {
  const b = random().slice(0, 16)
  b[6] = (b[6]! & 0x0f) | 0x40
  b[8] = (b[8]! & 0x3f) | 0x80
  const hex = [...b].map((x) => x.toString(16).padStart(2, '0')).join('')
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
}
