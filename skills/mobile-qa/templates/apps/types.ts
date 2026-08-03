/**
 * The keystone contract: one harness, many apps.
 *
 * Shared flows (`flows/*.ts`) contain ZERO app-specific strings. They ask for a
 * logical step name; this config maps it to that app's real test id.
 */

export type AppKind = 'react-native' | 'capacitor' | 'native'

/**
 * Logical step names the shared flows use. Adding a name here makes every app
 * config fail to compile until it supplies an id — which is the point.
 */
export type SelectorName =
  // login
  | 'usernameField'
  | 'passwordField'
  | 'submitButton'
  | 'homeMarker'
  | 'errorBanner'
  // form
  | 'itemNameField'
  | 'itemNotesField'
  | 'successBanner'
  // crud
  | 'createButton'
  | 'itemRow'
  | 'editButton'
  | 'deleteButton'
  | 'confirmButton'
  | 'emptyState'

export interface AppConfig {
  /** Registry key — must match the filename and the `APP` env value. */
  readonly id: string
  readonly name: string
  /** Decides how a test id is turned into a selector, and whether we drive the webview. */
  readonly kind: AppKind

  readonly appPackage: string
  readonly appActivity: string
  /** Path to an .apk/.aab. Given → installed fresh each run. Omitted → attach to the installed app. */
  readonly apkPath?: string

  /** Override the device the run targets. Falls back to env, then the first attached device. */
  readonly deviceName?: string
  readonly platformVersion?: string

  /** Capacitor only. Defaults to `WEBVIEW_<appPackage>`. */
  readonly webviewContext?: string

  readonly selectors: Readonly<Record<SelectorName, string>>
}
