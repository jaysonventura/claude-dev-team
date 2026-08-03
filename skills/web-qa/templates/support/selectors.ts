import type { Locator, Page } from '@playwright/test'

import type { AppConfig, Selector, SelectorName } from '../apps/types.js'

/**
 * Anything you can locate inside: a `Page`, or a `Locator` when scoping to a
 * row. Both expose the same four query methods, which is all we ever use.
 */
export type Queryable = Pick<Page, 'getByRole' | 'getByLabel' | 'getByText' | 'getByTestId'>

/**
 * Resolve a logical step name to a Locator. The one place that knows how each
 * app exposes each control.
 *
 * Policy: role → label → text → test id. No XPath and no coordinates — XPath
 * encodes the DOM shape rather than what the user perceives, and coordinates
 * assert nothing at all.
 */
export function locate(scope: Queryable, app: AppConfig, name: SelectorName): Locator {
  return fromSelector(scope, app.selectors[name])
}

function fromSelector(scope: Queryable, selector: Selector): Locator {
  switch (selector.by) {
    case 'role':
      return scope.getByRole(selector.role, { name: selector.name, exact: selector.exact })
    case 'label':
      return scope.getByLabel(selector.text, { exact: selector.exact })
    case 'text':
      return scope.getByText(selector.text, { exact: selector.exact })
    case 'testId':
      return scope.getByTestId(selector.id)
    default: {
      const unreachable: never = selector
      throw new Error(`Unsupported selector: ${JSON.stringify(unreachable)}`)
    }
  }
}
