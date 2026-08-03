import type { AppConfig } from './types.js'

/**
 * Example customer-facing app. Selectors here lean on `role` and `label`,
 * because that is what a user perceives — a control that cannot be reached by
 * role or label is usually an accessibility bug worth fixing in the app rather
 * than routing around with a test id.
 */
export const app: AppConfig = {
  id: 'example-app',
  name: 'Example App',
  baseURL: process.env.QA_EXAMPLE_APP_URL ?? 'http://localhost:3000',

  routes: {
    signIn: '/sign-in',
    home: '/',
    items: '/items',
    adminOnly: '/admin',
    files: '/files',
  },

  roles: {
    user: { usernameEnv: 'QA_EXAMPLE_APP_USER_USERNAME', passwordEnv: 'QA_EXAMPLE_APP_USER_PASSWORD' },
    admin: { usernameEnv: 'QA_EXAMPLE_APP_ADMIN_USERNAME', passwordEnv: 'QA_EXAMPLE_APP_ADMIN_PASSWORD' },
  },

  selectors: {
    usernameField: { by: 'label', text: 'Email' },
    passwordField: { by: 'label', text: 'Password' },
    signInButton: { by: 'role', role: 'button', name: 'Sign in' },
    signedInMarker: { by: 'role', role: 'button', name: 'Account' },
    signInError: { by: 'role', role: 'alert' },
    adminAreaMarker: { by: 'role', role: 'heading', name: 'Admin' },
    accessDeniedMarker: { by: 'text', text: /not authorized/i },

    itemNameField: { by: 'label', text: 'Name' },
    itemNotesField: { by: 'label', text: 'Notes' },
    saveButton: { by: 'role', role: 'button', name: 'Save' },
    successMessage: { by: 'role', role: 'status' },
    validationError: { by: 'role', role: 'alert' },

    createButton: { by: 'role', role: 'button', name: 'New item' },
    itemRow: { by: 'role', role: 'listitem' },
    editButton: { by: 'role', role: 'button', name: 'Edit' },
    deleteButton: { by: 'role', role: 'button', name: 'Delete' },
    confirmButton: { by: 'role', role: 'button', name: 'Confirm' },
    emptyState: { by: 'text', text: 'No items yet' },

    fileInput: { by: 'label', text: 'Choose file' },
    uploadButton: { by: 'role', role: 'button', name: 'Upload' },
    uploadedFileMarker: { by: 'testId', id: 'uploaded-file' },
    downloadButton: { by: 'role', role: 'button', name: 'Download' },
  },
}
