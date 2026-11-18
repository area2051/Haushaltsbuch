import * as Dialog from '@radix-ui/react-dialog'
import { X } from 'lucide-react'
import type { ReactNode } from 'react'
import { Drawer } from 'vaul'
import { cn } from '../../lib/cn'
import { useIsDesktop } from '../../lib/useMedia'

type Props = {
  open: boolean
  onOpenChange(open: boolean): void
  title: string
  /** Visually hidden title (the sheet shows its own heading). */
  hideTitle?: boolean
  description?: string
  children: ReactNode
  className?: string
}

/** Bottom sheet on phones (swipe to close), centered dialog on desktop. */
export function Sheet({ open, onOpenChange, title, hideTitle, description, children, className }: Props) {
  const desktop = useIsDesktop()
  const heading = (Title: typeof Dialog.Title) => (
    <div className={cn('mb-4 flex items-center justify-between gap-4', hideTitle && 'sr-only')}>
      <Title className="text-xl font-semibold tracking-tight">{title}</Title>
    </div>
  )

  if (desktop) {
    return (
      <Dialog.Root open={open} onOpenChange={onOpenChange}>
        <Dialog.Portal>
          <Dialog.Overlay className="fixed inset-0 z-40 bg-black/30 backdrop-blur-[2px] data-[state=open]:animate-[fade_.2s]" />
          <Dialog.Content
            aria-describedby={description ? undefined : undefined}
            className={cn(
              'fixed left-1/2 top-1/2 z-50 max-h-[88vh] w-[min(560px,calc(100vw-32px))] -translate-x-1/2 -translate-y-1/2 overflow-y-auto rounded-[28px] bg-bg p-6 shadow-float outline-none',
              className,
            )}
          >
            {heading(Dialog.Title)}
            {description && <Dialog.Description className="sr-only">{description}</Dialog.Description>}
            <Dialog.Close asChild>
              <button aria-label="Schließen" className="absolute right-4 top-4 grid size-9 place-items-center rounded-full text-ink-3 hover:bg-tile-2 hover:text-ink">
                <X className="size-5" />
              </button>
            </Dialog.Close>
            {children}
          </Dialog.Content>
        </Dialog.Portal>
      </Dialog.Root>
    )
  }

  return (
    <Drawer.Root open={open} onOpenChange={onOpenChange} repositionInputs={false}>
      <Drawer.Portal>
        <Drawer.Overlay className="fixed inset-0 z-40 bg-black/30" />
        <Drawer.Content
          className={cn('fixed inset-x-0 bottom-0 z-50 flex max-h-[94dvh] flex-col rounded-t-[28px] bg-bg outline-none', className)}
        >
          <div aria-hidden className="mx-auto mb-1 mt-2.5 h-1.5 w-10 shrink-0 rounded-full bg-tile-3" />
          <div className="overflow-y-auto px-5 pb-[calc(env(safe-area-inset-bottom)+20px)] pt-3">
            {heading(Drawer.Title as unknown as typeof Dialog.Title)}
            {description && <Drawer.Description className="sr-only">{description}</Drawer.Description>}
            {children}
          </div>
        </Drawer.Content>
      </Drawer.Portal>
    </Drawer.Root>
  )
}
