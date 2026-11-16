/** Same rules as the server (server/src/users/dto.ts). */
export const DISPLAY_NAME_MAX = 50

export function usernameProblem(u: string): 'empty' | 'format' | null {
  if (!u) return 'empty'
  return /^[a-z0-9._-]{3,32}$/.test(u) ? null : 'format'
}

export function passwordProblem(password: string, confirmation: string): 'empty' | 'short' | 'mismatch' | null {
  if (!password) return 'empty'
  if (password.length < 8) return 'short'
  if (password !== confirmation) return 'mismatch'
  return null
}
