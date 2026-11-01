# Venue Layout agent rules

Read `CONTRIBUTING.md` and `doc/compatibility.md` before changing SDK or dependency
constraints. Follow the dependency compatibility policy in `CONTRIBUTING.md`.

## Preserve supported consumers

- Do not raise minimum Dart, Flutter or dependency versions merely because a
  newer release exists or the development toolchain was upgraded.
- Use the oldest compatible version that supplies an actually required API or
  correctness/security fix. Prefer existing APIs when they preserve behavior.
- Keep compatible version ranges broad. Do not introduce `any`, unnecessary exact
  pins, forks or shipped dependency overrides to make resolution pass.
- Raise a minimum only for a concrete requirement. Record the requirement and
  excluded SDK/dependency versions in the changelog, then test the declared
  minimum and current SDKs. Preserve the minimum-SDK CI jobs.
- Exact pins need an explicit reason. The SVG compiler pin currently protects
  the exact converter identity in public import receipts; do not relax it while
  leaving those receipts inaccurate.
- Separate test-tool compatibility from runtime requirements. Consumer packages
  do not inherit development dependencies; do not raise runtime floors to fix
  an obsolete downgraded test runner.
- Remove dependencies only after checking direct imports and public behavior.
  A package still needed transitively is not a reduction of installed packages.

## Toolchain and release

Use FVM for Flutter/Dart and pnpm 11.24.0 with frozen lockfiles for JavaScript.
Run only one Flutter task on the workstation at a time and Flutter tests with
`--concurrency=1`. Keep the development SDK pin separate from public minimums.
Use the documented release workflows and immutable, tested package archives.
Publish the core before a wrapper version requiring it; never overwrite an
existing registry version or substitute a newly built archive for qualified bytes.
