/**
 * Hold the shortcut labels recorded in settings for this browser session. Contains the map the formula key listener reads. Reloading restores the catalog defaults.
 *
 * @file
 */

export type ShortcutOverrides = Readonly<Record<string, string>>
export const shortcutKey = ['settings', 'shortcuts'] as const
export const defaultOverrides: ShortcutOverrides = {}

/** Return the shortcut label to match, using a recorded override when this command has one. An empty override clears the default. */
export function shortcutLabel(commandId: string, defaultShortcut: string | undefined, overrides: Readonly<Record<string, string>> = defaultOverrides) {
  if (!Object.hasOwn(overrides, commandId)) return defaultShortcut
  const override = overrides[commandId]
  return override === '' ? undefined : override
}
