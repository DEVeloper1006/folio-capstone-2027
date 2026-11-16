/**
 * Render a single choice as a row of pressed buttons. Contains the option list and the button that reports the next value.
 *
 * @file
 */

/** Name one choice by its stored value and the text shown on its button. */
export interface SegmentedOption<TValue extends string> {
  value: TValue
  label: string
}

/** Receive the group's accessible name, the pressed value, and the choices that can replace it. */
export interface SegmentedControlProps<TValue extends string> {
  label: string
  value: TValue
  options: ReadonlyArray<SegmentedOption<TValue>>
  onValueChange: (value: TValue) => void
}

/** Mark the current value as pressed and report the value of the button that was activated. */
export function SegmentedControl<TValue extends string>({ label, value, options, onValueChange }: SegmentedControlProps<TValue>) {
  /** Draw one choice and report it when its button is activated. */
  function renderOption(option: SegmentedOption<TValue>) {
    /** Replace the pressed value with this choice. */
    function selectOption() {
      onValueChange(option.value)
    }

    return (
      <button type="button" key={option.value} aria-pressed={option.value === value} onClick={selectOption}>
        {option.label}
      </button>
    )
  }

  return (
    <div className="ui-segmented" role="group" aria-label={label}>
      {options.map(renderOption)}
    </div>
  )
}
