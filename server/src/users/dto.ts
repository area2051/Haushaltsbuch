import { z } from 'zod'

export const userDto = z.object({
  id: z.string().uuid(),
  username: z.string(),
  displayName: z.string(),
  isAdmin: z.boolean(),
})

export type UserDto = z.infer<typeof userDto>

export function toUserDto(row: UserDto): UserDto {
  return { id: row.id, username: row.username, displayName: row.displayName, isAdmin: row.isAdmin }
}
