/**
 * Render a notebook button in one of the shared visual styles. Contains the default action, quiet text, and icon variants.
 *
 * @file
 */

import type { ButtonHTMLAttributes } from 'react'

/** Choose the button's visual weight. Default matches Edit and Done, quiet matches add-cell actions, and icon matches the page menu trigger. */
export type ButtonVariant = 'default' | 'quiet' | 'icon'

/** Accept a native button's attributes and the shared visual variant. */
export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant
}

/** Render a button that keeps the caller's click behavior and accessible name. The variant selects only its appearance. */
export function Button({ variant = 'default', className, type = 'button', ...rest }: ButtonProps) {
  const buttonClassName = ['ui-button', `ui-button-${variant}`, className].filter(Boolean).join(' ')
  return <button type={type} className={buttonClassName} {...rest} />
}
