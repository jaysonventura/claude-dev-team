---
name: clean-code-typescript
description: Use when writing or reviewing TypeScript/JavaScript. Conventions for strict types, naming, immutability, and control flow that keep TS code safe and readable.
---

# Clean code — TypeScript

## Types
- **No `any`.** Use precise types, `unknown` at boundaries (then narrow), generics for reuse. Enable
  `strict` (incl. `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes` where feasible).
- **Derive, don't duplicate:** `ReturnType`, `Parameters`, `Pick`/`Omit`, `as const`, template literal
  types. Single source of truth for shapes (infer from schema/zod where possible).
- **Make illegal states unrepresentable:** discriminated unions over boolean flags; narrow with
  exhaustive `switch` + a `never` default.

## Values & flow
- Prefer **immutability**: `const`, `readonly`, `ReadonlyArray`; return new objects over mutation.
- **Early returns / guard clauses** over deep nesting. Handle errors and edge cases first.
- No magic values — name constants. Avoid `==` (use `===`); avoid truthiness traps with `0`/`""`.
- Handle `null`/`undefined` explicitly (`?.`, `??`); don't `!`-assert away real possibilities.

## Naming & structure
- Intention-revealing names; verbs for functions, nouns for data; no abbreviations that aren't standard.
- One responsibility per function/module; keep files focused (see `code-splitting`).
- Async: always handle rejections; don't mix callbacks and promises; avoid floating promises.

## Review checklist
`any`/unsafe casts? unhandled null? non-exhaustive union? mutation that should be pure? magic number?
name that lies? Fix before approving.
