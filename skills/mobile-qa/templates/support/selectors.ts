import type { AppConfig, SelectorName } from '../apps/types.js'

const escapeForRegExp = (value: string): string => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
const escapeForQuotes = (value: string): string => value.replace(/(["\\])/g, '\\$1')

/**
 * Stable Android strategies only. No XPath helper — XPath depends on the view
 * hierarchy, which changes every time someone nudges a layout.
 */
export const by = {
  /** Accessibility id: Android `content-desc`, i.e. RN `accessibilityLabel`. */
  testId: (id: string): string => `~${id}`,

  /** Visible text. Use when a control genuinely has no test id. */
  label: (text: string): string => `android=new UiSelector().text("${escapeForQuotes(text)}")`,

  /**
   * Android `resource-id`. React Native puts `testID` here, bare on modern RN
   * but package-prefixed on some setups — match both rather than guess.
   */
  resourceId: (id: string): string =>
    `android=new UiSelector().resourceIdMatches("^(?:.+:id/)?${escapeForRegExp(id)}$")`,
} as const

/**
 * Resolve a logical step name to a selector for this app. The one place that
 * knows how each app kind exposes its test ids.
 *
 * `suffix` builds per-row selectors from a `testID={`item-${id}`}` convention.
 */
export function sel(app: AppConfig, name: SelectorName, suffix?: string): string {
  const id = suffix === undefined ? app.selectors[name] : `${app.selectors[name]}-${suffix}`

  switch (app.kind) {
    case 'capacitor':
      // DOM selector — only valid inside the webview context (see support/context.ts).
      return `[data-testid="${escapeForQuotes(id)}"]`
    case 'react-native':
      return by.resourceId(id)
    case 'native':
      return by.testId(id)
    default: {
      const unreachable: never = app.kind
      throw new Error(`Unsupported app kind: ${String(unreachable)}`)
    }
  }
}
