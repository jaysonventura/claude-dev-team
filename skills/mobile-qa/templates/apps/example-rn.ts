import type { AppConfig } from './types.js'

/**
 * React Native example.
 *
 * On Android, RN's `testID` surfaces as the view's `resource-id`; the values
 * below are the raw `testID` strings from the app source. RN's
 * `accessibilityLabel` maps to `content-desc` instead — if a component sets
 * only a label and no testID, give this app `kind: 'native'` or add the testID.
 */
export const app: AppConfig = {
  id: 'example-rn',
  name: 'Example RN App',
  kind: 'react-native',

  appPackage: 'com.example.rnapp',
  appActivity: '.MainActivity',
  // apkPath: './builds/example-rn-debug.apk',

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
