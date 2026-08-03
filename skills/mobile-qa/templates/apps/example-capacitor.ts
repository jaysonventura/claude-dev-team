import type { AppConfig } from './types.js'

/**
 * Ionic Capacitor example.
 *
 * The UI is a webview, so the values below are DOM `data-testid` attributes and
 * the flows run inside `WEBVIEW_<appPackage>` (see support/context.ts).
 * Set `webviewContext` only if the app names its webview something else.
 */
export const app: AppConfig = {
  id: 'example-capacitor',
  name: 'Example Capacitor App',
  kind: 'capacitor',

  appPackage: 'com.example.capacitorapp',
  appActivity: '.MainActivity',
  // webviewContext: 'WEBVIEW_com.example.capacitorapp',

  selectors: {
    usernameField: 'login-username',
    passwordField: 'login-password',
    submitButton: 'login-submit',
    homeMarker: 'home-screen',
    errorBanner: 'error-banner',

    itemNameField: 'item-name',
    itemNotesField: 'item-notes',
    successBanner: 'success-banner',

    createButton: 'items-create',
    itemRow: 'item',
    editButton: 'item-edit',
    deleteButton: 'item-delete',
    confirmButton: 'confirm-destructive',
    emptyState: 'items-empty',
  },
}
