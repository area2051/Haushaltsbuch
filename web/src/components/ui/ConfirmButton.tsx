import { AnimatePresence, motion } from 'motion/react'
import { useState } from 'react'
import { Button } from './Button'

/** Destructive button that asks inline before acting (no stacked dialogs inside sheets). */
export function ConfirmButton({
  label,
  question,
  confirmLabel,
  onConfirm,
  disabled,
}: {
  label: string
  question: string
  confirmLabel: string
  onConfirm(): void
  disabled?: boolean
}) {
  const [asking, setAsking] = useState(false)
  return (
    <AnimatePresence mode="wait" initial={false}>
      {asking ? (
        <motion.div key="ask" initial={{ opacity: 0, y: 4 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }} className="rounded-2xl bg-neg-soft p-4">
          <p role="alert" className="mb-3 text-[15px] font-medium text-neg">
            {question}
          </p>
          <div className="grid grid-cols-2 gap-2">
            <Button onClick={() => setAsking(false)}>Abbrechen</Button>
            <Button variant="primary" className="!bg-neg !text-white" onClick={onConfirm} disabled={disabled}>
              {confirmLabel}
            </Button>
          </div>
        </motion.div>
      ) : (
        <motion.div key="btn" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
          <Button variant="danger" size="lg" className="w-full" onClick={() => setAsking(true)} disabled={disabled}>
            {label}
          </Button>
        </motion.div>
      )}
    </AnimatePresence>
  )
}
