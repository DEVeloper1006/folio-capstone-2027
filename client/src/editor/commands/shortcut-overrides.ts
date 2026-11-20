/**
 * Define the shared shortcut override map read by formula and workspace key listeners. The settings loader restores persisted bindings into this cache; missing overrides use catalog defaults.
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
