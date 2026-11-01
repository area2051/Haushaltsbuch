import { z } from 'zod'

export const userDto = z.object({
  id: z.string().uuid(),
  username: z.string(),
  displayName: z.string(),
  isAdmin: z.boolean(),
}).meta({ id: 'UserDto' })

export type UserDto = z.infer<typeof userDto>

export function toUserDto(row: UserDto): UserDto {
  return { id: row.id, username: row.username, displayName: row.displayName, isAdmin: row.isAdmin }
}

export const usernameSchema = z.string().min(3).max(32).regex(/^[a-z0-9._-]+$/)
export const displayNameSchema = z.string().min(1).max(50)
export const passwordSchema = z.string().min(8)

/** Body for creating a user: used by `POST /setup` (first admin) and `POST /users`. */
export const setupBody = z.object({
  username: usernameSchema,
  displayName: displayNameSchema,
  password: passwordSchema,
}).meta({ id: 'SetupRequest' })
