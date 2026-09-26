# Afterhours

A macOS menu bar app that keeps a Mac awake while coding agents work, plus its marketing site. Read this section before the Ultracite rules below, which only cover the JavaScript side of the repo.

## Layout

- `apps/macos` holds the app (`Afterhours`) and the hook CLI (`afterhours-hook`). Both are Swift 6 executables built from one SwiftPM manifest, targeting macOS 14 and later.
- `packages/core` holds `AfterhoursCore`, the library both executables share: process inspection, session files, and subscription usage readers. It stays nonisolated so callers decide where its code runs.
- `apps/web` is the Next.js 16 marketing site. Bun workspaces and Turborepo tie the three packages together.

## Build the app

- `./apps/macos/scripts/build-app.sh` builds `apps/macos/build/Afterhours.app` with plain `swiftc`, so it works with the Command Line Tools alone. Set `ARCHS=arm64` for a faster single-arch build, and add `--install` to copy the app to `/Applications` and launch it. CI runs this script; don't switch it to `swift build`.
- The executables compile with `-default-isolation MainActor`. `AfterhoursCore` doesn't, because it's a library and callers should decide where its code runs.
- `./apps/macos/scripts/package-app.sh` turns an existing build into the `.dmg`, `.zip`, and checksums for a release.

## Snapshot the menu and Settings

`Afterhours --snapshot out.png [expanded]` renders the menu with sample data and writes it to a PNG. `Afterhours --snapshot-settings out.png [general|power|agents|limits|hub]` renders one Settings tab the same way. Judge a visual change by opening the PNG, not by reading the view code.

## Restart the app on a closed lid

The app holds a closed Mac awake with IOKit power assertions that die the instant the process exits. Killing or relaunching it lets a closed Mac fall into clamshell sleep within about a second, even on AC power, cutting remote clients like T3 Code or SSH. Run `caffeinate -s -t 300 &` before you kill, relaunch, or `--install` a build on a closed laptop.

## Verify changes

- `bun run check` runs Ultracite (oxlint and oxfmt) over JS, TS, CSS, and Markdown. It doesn't touch Swift.
- `swift test --package-path packages/core` runs the core tests with Swift Testing. CI runs it on `macos-26`. Local `swift test` needs a working SwiftPM and Swift Testing toolchain, so treat CI as the source of truth.
- `bunx turbo run build --filter=@afterhours/web` builds the site.
- CI only builds the apps Turborepo marks as affected. A change under `packages/core` counts as a change to the macOS app.

## Swift conventions

- Comment only to explain why, not what. Doc comments are one sentence.
- Members default to `private`. Errors are `NSError(domain: "Afterhours", code:, userInfo: [NSLocalizedDescriptionKey: "..."])`, with a message the menu can show as `lastError`.
- The app has no third-party Swift dependencies. Keep AppKit and `Bundle.main` out of `AfterhoursCore`.
- Anything that changes system state through `sudo` must be undone in `AppModel.releaseAll()`.

## Website conventions

- TSX files carry no comments. Compose classes with `cn` and `cva` (see `apps/web/components/pill.ts`) instead of hoisting class strings into constants.
- `apps/web/components/site.ts` reads the app version from `apps/macos/package.json` and lists agents by hand. That list mirrors `apps/macos/Sources/Afterhours/Agents.swift` and the README's list; update all three together, along with the matching logo in `apps/macos/Resources/agents` and `apps/web/public/agents`.

## Release

- A user-facing change to the app needs a changeset: run `bun changeset`, choose `@afterhours/macos`, and write the summary in the second person for the changelog. Changesets ignores `@afterhours/core` and `@afterhours/web`.
- Merging to `main` lets the Release workflow open a "Version Packages" pull request. Merging that tags `@afterhours/macos@x.y.z` and uploads the `.dmg` and `.zip`.
- PR titles follow `type: Capitalized subject`, where `type` is one of `fix feat chore ci docs refactor perf test style` and no scope is allowed. Commit subjects follow the same shape without the type.

---

# Ultracite Code Standards

This project uses **Ultracite**, a zero-config preset that enforces strict code quality standards through automated formatting and linting.

## Quick Reference

- **Format code**: `bun x ultracite fix`
- **Check for issues**: `bun x ultracite check`
- **Diagnose setup**: `bun x ultracite doctor`

Oxlint + Oxfmt (the underlying engine) provides robust linting and formatting. Most issues are automatically fixable.

---

## Core Principles

Write code that is **accessible, performant, type-safe, and maintainable**. Focus on clarity and explicit intent over brevity.

### Type Safety & Explicitness

- Use explicit types for function parameters and return values when they enhance clarity
- Prefer `unknown` over `any` when the type is genuinely unknown
- Use const assertions (`as const`) for immutable values and literal types
- Leverage TypeScript's type narrowing instead of type assertions
- Use meaningful variable names instead of magic numbers - extract constants with descriptive names

### Modern JavaScript/TypeScript

- Use arrow functions for callbacks and short functions
- Prefer `for...of` loops over `.forEach()` and indexed `for` loops
- Use optional chaining (`?.`) and nullish coalescing (`??`) for safer property access
- Prefer template literals over string concatenation
- Use destructuring for object and array assignments
- Use `const` by default, `let` only when reassignment is needed, never `var`

### Async & Promises

- Always `await` promises in async functions - don't forget to use the return value
- Use `async/await` syntax instead of promise chains for better readability
- Handle errors appropriately in async code with try-catch blocks
- Don't use async functions as Promise executors

### React & JSX

- Use function components over class components
- Call hooks at the top level only, never conditionally
- Specify all dependencies in hook dependency arrays correctly
- Use the `key` prop for elements in iterables (prefer unique IDs over array indices)
- Nest children between opening and closing tags instead of passing as props
- Don't define components inside other components
- Use semantic HTML and ARIA attributes for accessibility:
  - Provide meaningful alt text for images
  - Use proper heading hierarchy
  - Add labels for form inputs
  - Include keyboard event handlers alongside mouse events
  - Use semantic elements (`<button>`, `<nav>`, etc.) instead of divs with roles

### Error Handling & Debugging

- Remove `console.log`, `debugger`, and `alert` statements from production code
- Throw `Error` objects with descriptive messages, not strings or other values
- Use `try-catch` blocks meaningfully - don't catch errors just to rethrow them
- Prefer early returns over nested conditionals for error cases

### Code Organization

- Keep functions focused and under reasonable cognitive complexity limits
- Extract complex conditions into well-named boolean variables
- Use early returns to reduce nesting
- Prefer simple conditionals over nested ternary operators
- Group related code together and separate concerns

### Security

- Add `rel="noopener"` when using `target="_blank"` on links
- Avoid `dangerouslySetInnerHTML` unless absolutely necessary
- Don't use `eval()` or assign directly to `document.cookie`
- Validate and sanitize user input

### Performance

- Avoid spread syntax in accumulators within loops
- Use top-level regex literals instead of creating them in loops
- Prefer specific imports over namespace imports
- Avoid barrel files (index files that re-export everything)
- Use proper image components (e.g., Next.js `<Image>`) over `<img>` tags

### Framework-Specific Guidance

**Next.js:**

- Use Next.js `<Image>` component for images
- Use `next/head` or App Router metadata API for head elements
- Use Server Components for async data fetching instead of async Client Components

**React 19+:**

- Use ref as a prop instead of `React.forwardRef`

**Solid/Svelte/Vue/Qwik:**

- Use `class` and `for` attributes (not `className` or `htmlFor`)

---

## Testing

- Write assertions inside `it()` or `test()` blocks
- Avoid done callbacks in async tests - use async/await instead
- Don't use `.only` or `.skip` in committed code
- Keep test suites reasonably flat - avoid excessive `describe` nesting

## When Oxlint + Oxfmt Can't Help

Oxlint + Oxfmt's linter will catch most issues automatically. Focus your attention on:

1. **Business logic correctness** - Oxlint + Oxfmt can't validate your algorithms
2. **Meaningful naming** - Use descriptive names for functions, variables, and types
3. **Architecture decisions** - Component structure, data flow, and API design
4. **Edge cases** - Handle boundary conditions and error states
5. **User experience** - Accessibility, performance, and usability considerations
6. **Documentation** - Add comments for complex logic, but prefer self-documenting code

---

Most formatting and common issues are automatically fixed by Oxlint + Oxfmt. Run `bun x ultracite fix` before committing to ensure compliance.
