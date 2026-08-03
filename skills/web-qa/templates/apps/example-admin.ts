import type { AppConfig } from './types.js'

/**
 * A second app on a different origin, proving the flows are reusable: the same
 * `flows/` drive this without a line of app-specific code.
 *
 * It differs from `example-app` on purpose — its own base URL, its own
 * credential env vars, a `data-qa` test id attribute, and several controls
 * reached by test id because this back-office UI has icon-only buttons with no
 * accessible name. That is the intended fallback, not the default.
 */
export const app: AppConfig = {
  id: 'example-admin',
  name: 'Example Admin Console',
  baseURL: process.env.QA_EXAMPLE_ADMIN_URL ?? 'http://localhost:3001',

  routes: {
    signIn: '/login',
    home: '/dashboard',
    items: '/records',
    adminOnly: '/settings/users',
    files: '/settings/files',
  },

  roles: {
    user: { usernameEnv: 'QA_EXAMPLE_ADMIN_STAFF_USERNAME', passwordEnv: 'QA_EXAMPLE_ADMIN_STAFF_PASSWORD' },
    admin: { usernameEnv: 'QA_EXAMPLE_ADMIN_OWNER_USERNAME', passwordEnv: 'QA_EXAMPLE_ADMIN_OWNER_PASSWORD' },
  },

  testIdAttribute: 'data-qa',

  selectors: {
    usernameField: { by: 'label', text: 'Username' },
    passwordField: { by: 'label', text: 'Password' },
    signInButton: { by: 'role', role: 'button', name: 'Log in' },
    signedInMarker: { by: 'role', role: 'navigation', name: 'Main' },
    signInError: { by: 'role', role: 'alert' },
    adminAreaMarker: { by: 'role', role: 'heading', name: 'User settings' },
    accessDeniedMarker: { by: 'text', text: /permission/i },

    itemNameField: { by: 'label', text: 'Title' },
    itemNotesField: { by: 'label', text: 'Description' },
    saveButton: { by: 'role', role: 'button', name: 'Save record' },
    successMessage: { by: 'role', role: 'status' },
    validationError: { by: 'role', role: 'alert' },

    createButton: { by: 'role', role: 'button', name: 'Add record' },
    itemRow: { by: 'role', role: 'row' },
    // Icon-only buttons: no accessible name to match on, so a test id it is.
    editButton: { by: 'testId', id: 'record-edit' },
    deleteButton: { by: 'testId', id: 'record-delete' },
    confirmButton: { by: 'role', role: 'button', name: 'Yes, delete' },
    emptyState: { by: 'text', text: 'No records' },

    fileInput: { by: 'label', text: 'Choose file' },
    uploadButton: { by: 'role', role: 'button', name: 'Upload' },
    uploadedFileMarker: { by: 'testId', id: 'uploaded-file' },
    downloadButton: { by: 'role', role: 'button', name: 'Download' },
  },
}
