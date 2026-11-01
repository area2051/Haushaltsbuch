import { Algorithm, hash, verify } from '@node-rs/argon2'

// OWASP-recommended argon2id parameters (19 MiB, 2 iterations, 1 lane).
const HASH_OPTIONS = { algorithm: Algorithm.Argon2id, memoryCost: 19456, timeCost: 2, parallelism: 1 }

export function hashPassword(plain: string): Promise<string> {
  return hash(plain, HASH_OPTIONS)
}

export async function verifyPassword(hashed: string, plain: string): Promise<boolean> {
  try {
    return await verify(hashed, plain)
  } catch {
    return false
  }
}
