import type { Page } from '@playwright/test'

/**
 * The keystone contract: one harness, many apps.
 *
 * Shared flows (`flows/*.ts`) contain ZERO app-specific strings. They ask for a
 * logical step name; this config maps it to that app's real accessible name,
 * label, text or test id.
 */

type GetByRoleArgs = Parameters<Page['getByRole']>
/** Derived from Playwright rather than re-typed, so it tracks the installed version. */
export type AriaRole = GetByRoleArgs[0]
type RoleName = NonNullable<NonNullable<GetByRoleArgs[1]>['name']>

/**
 * Selector policy, in order: role → label → text → test id.
 *
 * `role` first because it asserts the accessibility tree, which is what a user
 * (and a screen reader) actually sees. `testId` is the escape hatch for
 * controls with no accessible name. There is deliberately no XPath and no
 * coordinate variant — both break on any layout change and assert nothing.
 */
export type Selector =
  | { readonly by: 'role'; readonly role: AriaRole; readonly name?: RoleName; readonly exact?: boolean }
  | { readonly by: 'label'; readonly text: string | RegExp; readonly exact?: boolean }
  | { readonly by: 'text'; readonly text: string | RegExp; readonly exact?: boolean }
  | { readonly by: 'testId'; readonly id: string }

/**
 * Logical step names the shared flows use. Adding a name here makes every app
 * config fail to compile until it supplies a selector — which is the point.
 */
export type SelectorName =
  // auth
  | 'usernameField'
  | 'passwordField'
  | 'signInButton'
  | 'signedInMarker'
  | 'signInError'
  | 'adminAreaMarker'
  | 'accessDeniedMarker'
  // forms
  | 'itemNameField'
  | 'itemNotesField'
  | 'saveButton'
  | 'successMessage'
  | 'validationError'
  // crud
  | 'createButton'
  | 'itemRow'
  | 'editButton'
  | 'deleteButton'
  | 'confirmButton'
  | 'emptyState'
  // upload / download
  | 'fileInput'
  | 'uploadButton'
  | 'uploadedFileMarker'
  | 'downloadButton'

/** Every app declares both roles, so "a user must NOT reach the admin area" is testable. */
export type UserRole = 'user' | 'admin'

/**
 * Where a role's credentials live — the NAMES of two env vars, never the values.
 * Keeping names here means a config file can be committed and a credential cannot.
 */
export interface RoleConfig {
  readonly usernameEnv: string
  readonly passwordEnv: string
}

export interface RouteConfig {
  readonly signIn: string
  readonly home: string
  readonly items: string
  /** Reachable by `admin`, refused for `user`. */
  readonly adminOnly: string
  /** Where file upload/download lives. */
  readonly files: string
}

export interface AppConfig {
  /** Registry key — must match the filename and the `APP` env value. */
  readonly id: string
  readonly name: string
  /** Origin under test. Read from env with a localhost default; never a production URL. */
  readonly baseURL: string

  readonly routes: RouteConfig
  readonly roles: Readonly<Record<UserRole, RoleConfig>>

  /** Attribute behind `getByTestId`. Playwright's default is `data-testid`. */
  readonly testIdAttribute?: string

  readonly selectors: Readonly<Record<SelectorName, Selector>>

  /**
   * Console/network noise this app is known to emit that must not fail a run —
   * a third-party widget's 500, say. Keep this list short and justified; it is
   * the only way a real error escapes `support/console.ts`.
   */
  readonly allowedPageIssues?: readonly RegExp[]
}
