import { forwardRef, type InputHTMLAttributes, type ReactNode, type SelectHTMLAttributes, useId } from 'react'
import { cn } from '../../lib/cn'

const control =
  'h-12 w-full rounded-2xl bg-tile-2 px-4 text-[16px] text-ink outline-none ring-accent/40 transition placeholder:text-ink-3 focus:bg-tile focus:ring-2'

export function Field({ label, error, hint, children }: { label: string; error?: string | null; hint?: string; children: (id: string) => ReactNode }) {
  const id = useId()
  return (
    <div className="space-y-1.5">
      <label htmlFor={id} className="block px-1 text-[13px] font-medium text-ink-2">
        {label}
      </label>
      {children(id)}
      {error ? <p className="px-1 text-[13px] text-neg">{error}</p> : hint ? <p className="px-1 text-[13px] text-ink-3">{hint}</p> : null}
    </div>
  )
}

export const Input = forwardRef<HTMLInputElement, InputHTMLAttributes<HTMLInputElement>>(function Input({ className, ...rest }, ref) {
  return <input ref={ref} className={cn(control, className)} {...rest} />
})

export function Select({ className, ...rest }: SelectHTMLAttributes<HTMLSelectElement>) {
  return <select className={cn(control, 'appearance-none bg-[length:16px] pr-10', className)} {...rest} />
}
