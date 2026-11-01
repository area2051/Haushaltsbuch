import { z } from 'zod'

export const userDto = z.object({
  id: z.string().uuid(),
  username: z.string(),
  displayName: z.string(),
  isAdmin: z.boolean(),
})

export type UserDto = z.infer<typeof userDto>
