# Working on Cindel

These instructions apply throughout this monorepo. Follow the user's explicit
scope and authorization. Read more specific instructions in the affected
directory before making changes.

## Product contract

- Cindel promises **the same public API and application code across MDBX,
  SQLite native, and SQLite Web/OPFS**. Backends may optimize their internals,
  but must preserve the same generated, typed behavior.
- Do not solve a backend defect by requiring platform-specific application
  code, an untyped workaround, or a separate public API.
- Protect transaction isolation, atomicity, rollback, ID allocation, type and
  integer precision, ordering, relationship integrity, and error propagation.
- Performance matters. Do not trade speed or memory for speculative cleanup.
  A demonstrated correctness bug can justify a measured cost; explain the
  tradeoff and alternatives instead of claiming an improvement without evidence.
- MDBX is vendored and its parameters are intentionally tuned. Do not change
  its version or tuning without an explicit request.

## Repository map

- `packages/cindel`: public Dart runtime, generated API integration, native
  bindings, tests, and the Rust core under `native/`.
- `packages/cindel_annotations`: annotations and shared schema metadata.
- `packages/cindel_generator`: schema, serializer, and typed API generation.
- `packages/cindel_flutter_libs`: Flutter packaging, native binaries, and Web
  Worker/Wasm assets, including CocoaPods and Swift Package Manager support.
- `packages/cindel/README.md`: quick introduction and essential usage.
  The root `README.md` is a symlink to this file.
- `docs/documentation/`: detailed behavior, explanations, and examples.
- `ROADMAP.md`: delivered capabilities, remaining work, and candidate work.
- `tool/prebuilt/` and `.github/workflows/`: build, packaging, validation, and
  release tooling. Inspect the current files before selecting commands.

## Investigate, demonstrate, propose, then implement

1. Read the request, inspect the current branch, working-tree status, and diff.
   Preserve existing user changes. Inspect the real implementation, generated
   paths, relevant tests, and history; documentation alone is not evidence.
2. For a suspected bug, identify the public operation, expected behavior,
   observed result, affected backends, and responsible code. Reproduce it with
   the smallest useful case. Compare with the original revision when assessing
   a regression. Distinguish a defect from an outdated test, intentional behavior,
   a stale binary, or an environment problem.
3. Propose a concrete, complete solution with a bounded scope: root cause,
   affected layers, compatibility, regression coverage, and expected cost.
   Do not repeatedly present fragments of the same unfinished solution.
4. **Do not modify production implementation until the user approves the
   solution or explicitly requests its implementation.** An analysis-only
   request stays read-only for implementation. Reproduction fixtures and
   investigative tests may be prepared within the authorized investigation.
   A direct implementation request is approval; do not ask again unnecessarily.
5. Implement only the approved solution. If investigation exposes a separate
   implementation defect, explain it and obtain scope approval before fixing it.
   Continue independent work already authorized.
6. Verify the fix and its public consequences, then review the complete final
   diff. Report what changed, the evidence, remaining limitations, and any cost.
   Do not declare completion while an authorized issue remains unresolved.

Use previous research as a guide, then reconcile it with current code and
commits. Do not reopen resolved items merely because the report is outdated,
invent pending work, or infer capabilities from feature lists. It is valid to
conclude that an investigation is complete. Keep SYNC, Web multitab, and the
example app outside unrelated core-library investigations unless requested.

## Changes and validation

- Prefer development on `dev` or another explicitly authorized branch. Check
  the branch first; do not edit `main`, merge, or switch branches by assumption.
- Make precise changes. Do not delete user code, fix unrelated warnings,
  refactor adjacent systems, add dependencies, or install tools without scope
  authorization. Fix defects introduced by your own work.
- Add meaningful regressions for confirmed bugs: demonstrate the original
  failure and the corrected result. Exercise the generated public API and
  `.where()` / `.filter()` paths when relevant, not only internal helpers.
- Verify equivalent behavior in MDBX, SQLite native, and Web for shared public
  operations. Cover the relevant edge cases, transaction rollback, and failure
  paths. Use controlled failures when testing error handling.
- Every new or modified Dart test must document intent in the existing format;
  a test without that documentation is incomplete. Follow the same convention
  for Rust tests, as described in `CONTRIBUTING.md`:

  ```dart
  // Scenario: The state or input being reproduced.
  // Covers:
  // - The rule, branch, or integration under test.
  // Expected: The observable result or side effect.
  test('describes the behavior.', () {
    // Arrange.
    // Act.
    // Assert.
  });
  ```

- Fix generated-code defects in the generator and regenerate the affected
  fixtures. Do not hand-edit generated output as the sole correction, suppress
  diagnostics to hide a defect, or weaken assertions just to make tests pass.
- For optimizations, compare before/after under equivalent conditions: build
  profile, toolchain, data, warmup, repetitions, and measured boundaries. Keep
  setup such as ID preparation outside timing when it is outside timing for
  the other implementations. Report actual time and memory measurements.
- Claims of bounded memory or fewer traversals require checks of retained
  objects, batches, candidates, scans, or polls as appropriate. A faster timing
  alone does not establish either claim.
- Verify which native binary or Web runtime a test actually loads. Rebuild the
  affected artifacts when necessary; do not mistake stale assets for a code
  defect or disable freshness/ABI checks to bypass a failure.
- Run checks appropriate to the change and the affected backends. Distinguish
  executed tests from static inspection, skipped tests, and unavailable platforms.
  Do not claim a full suite passed after running only targeted tests.
- Explain every relevant failure, including pre-existing failures. Do not
  silently omit it or change unrelated implementation to get a green result.
- Keep investigation downloads, reports, benchmark scratch data, and generated
  tool caches outside the tracked source tree. Retain focused regression fixtures
  and required generated test models; avoid adding hundreds of research files.
- Do not conflate Dart, Rust, or Wasm coverage. State which tests, sources, and
  exclusions produced each percentage. Preserve the existing coverage/Codecov
  workflow unless changes to it were requested.

## Tooling

- Use `dart`, `flutter`, and `cargo` from the active shell `PATH`. Do not hardcode
  machine-specific paths to those executables.
- With Codex shell tools, run Dart/Flutter/Cargo build, test, analyze, format,
  pub, and run commands outside the sandbox using
  `sandbox_permissions: "require_escalated"`. This also applies to scripts that
  invoke these tools or execute native binaries.
- Before Cargo commands in Windows PowerShell/pwsh, use:

  ```powershell
  $env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"
  ```

- Use `--locked` for Cargo builds/tests where supported. Do not silently update
  dependencies or lockfiles to make a check succeed.
- Read current SDK requirements from package/workspace pubspecs and pinned
  toolchains from the workflows. Do not copy historical version numbers from
  research notes or assume the local SDK matches the release runner.
- `tool/benchmark/` is ignored local tooling. If present, the frequently used
  `run_all_core_tests.ps1` must remain usable; inspect its current behavior
  before changing test execution. Do not rely on ignored scripts existing in
  a clean clone or place new tracked tools in ignored directories accidentally.

## Documentation and versioning

- Update affected tests, documentation, and package changelogs in the same
  approved implementation. Review `ROADMAP.md` and update it when the change
  affects a delivered capability, remaining item, or validation status.
  Do not mark an item complete without evidence or present planned work as shipped.
- Keep the README a concise introduction. Preserve important capabilities and
  sections, especially migrations; update, add, or simplify content without
  removing it unless requested. Put extended explanations and examples in
  `docs/documentation/`, and check examples against current generated APIs.
- Keep the README's `^x.y.z` placeholders. Do not replace them with release
  numbers as part of an unrelated content update. Shared README image references
  must work from the repository root, package directory, and pub.dev; use public
  absolute URLs for shared assets outside the published package.
- Use `tool/update_benchmark_svg.ps1` to refresh the benchmark SVG from a CSV.
  Updating benchmark data must not rewrite the README.
- Version modified publishable packages coherently for the agreed release.
  Include generator or annotations changes when those packages are affected;
  do not blindly bump unchanged packages. Distinguish release-worthy package
  changes from repository-only tooling or documentation corrections.
- Use the agreed development changelog section, with brief user-facing entries.
  Check dependent constraints, SDK minimums, podspec versions, and packaging
  metadata as applicable. Published versions are immutable; corrections need
  a new version. Do not invent the next release number when it is not agreed.
- If the native interface changes, update the ABI contract, bindings, loaders,
  verification tools, tests, and affected packaged native/Web artifacts together.
  Determine the current ABI from code; do not hardcode an old value from notes.

## CI, release, and Git

- Keep CI, release, and manual Apple validation separate. CI is reusable from
  release and can be dispatched manually; do not enable automatic CI on pushes
  to `dev` or change workflow triggers without explicit authorization.
- Use the dedicated manual Apple workflow when that validation is requested.
  Do not execute release or publish packages as a substitute for testing.
- Validate the final package, not just build directories: all platform artifacts
  must be from the intended run, match the required ABI, and survive Pub packaging.
  Use checksums to detect old binaries even when their ABI number matches.
- Use Pub dry-run and Pana when publication validation is in scope. State their
  real warnings and limitations. Local Windows checks do not replace macOS/Xcode
  consumer validation for SwiftPM and CocoaPods.
- Commit only when requested. For an unspecified commit request, inspect and
  include **all pending changes**, including user edits and deletions. Do not
  silently narrow the commit by inferred task scope or authorship.
- Write commit titles and bodies in English. Describe the concrete problem,
  resulting behavior, affected scope, validation actually performed, and any
  material unverified work. Keep descriptions concise and factual.
- Commit authorization does not authorize push, merge, tag creation/movement,
  release execution, or publication. Perform those actions only when requested.
  For requested fast-forward merges, use `--ff-only`; do not rewrite history
  or manufacture a merge commit if fast-forward is impossible.
- After a commit, report its hash, working-tree status, and whether it was pushed.
  After an authorized release, inspect the jobs and actual published archives
  before claiming that packages contain the correct binaries.
