---
name: proof-bearing-verification
description: Prove behavior before declaring engineering work complete.
version: 0.1.0
author: Wesley Matos, Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [verification, testing, evidence, quality, agents]
    related_skills: [test-driven-development, systematic-debugging, requesting-code-review]
  canonical: https://skills.wesleymatos.dev/standards/proof-bearing-verification/SKILL.md
---

# Proof-Bearing Verification

Use when reviewing existing implementation, delegated work, or delivery readiness. A green command, static review, or agent summary is not proof unless it exercises the claimed behavior.

## When to Use

- An agent says a task is complete.
- Tests pass but their behavioral strength is unknown.
- A bug fix, UI change, integration, or operational change needs validation.
- A static review conflicts with behavior previously verified at runtime.

Do not use this instead of `test-driven-development` for new code; use it to validate the evidence after or alongside implementation.

## Procedure

1. **Name the claimed behavior.**
   - State the user-visible or externally observable result being asserted.
   - Completion: the claim can be tested without referring to implementation details.

2. **Choose the nearest real seam.**
   - Prefer a mounted component interaction, integration request, CLI invocation, API call, or end-to-end flow over an import-only or snapshot-only test.
   - Use realistic payloads and production-shaped fixtures.
   - Completion: the probe reaches the code path whose behavior is being claimed.

3. **Prove the probe has teeth.**
   - For changed or removed behavior, first observe a failure without the implementation or with a deliberate no-op when safe.
   - A test that stays green when the changed unit is bypassed is vacuous and must not be used as evidence.
   - Completion: the probe can distinguish working behavior from the relevant broken behavior.

4. **Run and inspect the proof.**
   - Execute the focused check, then the project’s applicable broader checks.
   - Read the test or harness rather than trusting a summary from its author.
   - Completion: output and implementation both support the exact claim.

5. **Handle conflicting evidence.**
   - Treat user-verified runtime behavior as evidence requiring explanation before replacing it with a static-review recommendation.
   - Trace the framework, cache, infrastructure, or runtime semantics causing the apparent contradiction.
   - Completion: any change follows the strongest available evidence, not reviewer confidence.

## Pitfalls

- **Do not verify browser-console behavior with Node.** Node's `console.log` has no `%c` support — it treats style strings as plain args and silently discards them, so a Node/Python harness prints a clean grid and masks a broken DevTools rendering. To verify console output, drive the real browser over CDP (headless Chrome `--remote-debugging-port` + a WebSocket script capturing `Runtime.consoleAPICalled`), or get user-visible evidence from the actual console. A harness that runs on a different console engine is not proof.
- **A `console.log` with very many `%c` segments overflows DevTools.** The console formatter consumes args one specifier at a time; when a single call has too many styled segments (e.g. ~193), the tail style strings are not consumed as styles — they print literally as unformatted text (the classic `color:#...;font-family...` garbage dump). Remedy per Chrome docs: one `console.log` **per line/row**, each with a bounded number of `%c` runs. This is why per-character ASCII-art as one giant `console.log('%c%s%c%s...')` leaks styles.
- “Renders without throwing,” type-only fixtures, mocks that replace the unit under test, and `.todo()` tests do not prove behavior.
- Never change production behavior merely to satisfy shallow test scaffolding.
- Do not claim completion when an external dependency, UI interaction, or deployment path was not exercised; report the unverified boundary.

## Verification

A completion report must include: the behavior proved, the exact command or action used, the observed result, and any boundary that remains unverified.
