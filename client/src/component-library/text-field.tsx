/**
 * Render a labeled single-line input. Contains the label, the native input, and an optional suffix such as a unit.
 *
 * @file
 */

import { useId } from 'react'
import type { InputHTMLAttributes, ReactNode } from 'react'

/** Accept a visible label, an optional suffix, and the native input attributes except an id, which the field generates. */
export interface TextFieldProps extends Omit<InputHTMLAttributes<HTMLInputElement>, 'id'> {
  label: string
  suffix?: ReactNode
}

/** Connect a label to one input and leave value changes to the caller's input event. A suffix sits after the input when the value needs a unit. */
export function TextField({ label, suffix, ...rest }: TextFieldProps) {
  const fieldId = useId()
  const fieldClassName = suffix == null ? 'ui-field' : 'ui-field ui-field-with-suffix'

  return (
    <label className={fieldClassName} htmlFor={fieldId}>
      <span className="ui-field-label">{label}</span>
      <input id={fieldId} className="ui-field-input" {...rest} />
      {suffix == null ? null : <span className="ui-field-suffix">{suffix}</span>}
    </label>
  )
}
