# SDK and dependency compatibility

This contract applies to Flutter wrapper 0.4.4 and core 0.2.3. Wrapper 0.4.3
requires Dart 3.13 / Flutter 3.47.

The Flutter wrapper supports Dart **3.12+** and Flutter **3.44+**. The standalone
geometry core supports Dart **3.10+**. Development and distribution builds remain
pinned to Flutter 3.47.7; that pin is not the public minimum.

CI tests the wrapper on Flutter 3.44.0 with both the lowest allowed dependencies
and the latest compatible dependencies. The current-toolchain lane runs the
full source, example, browser and distribution gates. Core tests also run on its
minimum Dart SDK, bundled with Flutter 3.38.1, at both runtime resolution endpoints.
Core test tooling is resolved normally first; only the runtime dependencies are
downgraded, because historical test-tool transitive dependencies do not compile
on current Dart SDKs and are not dependencies of library consumers.
Dependency graphs are retained as CI artifacts, including the current-toolchain
graphs alongside the qualified npm release archive.

## Host integration

Use `package:material_ui/material_ui.dart` with the public Flutter widgets. The
standalone Material types and inherited themes must match the host's types.
`VenueLayoutLocalizations.localizationsDelegates` supplies the package and
standalone Material/Cupertino delegates; keep the host's other delegates too.
The package supports English and Czech messages and accepts host translations.

Material UI 1.0.1 is the oldest supported standalone Material release. Compatible
1.x updates are permitted, so older SDKs can resolve an older UI release while
current SDKs can resolve newer releases. There is one widget implementation,
without SDK-specific forks or host dependency overrides.

The only SDK Material boundary is inside the external color-picker integration:
`MaterialUiCompatibilityBridge` supplies its inherited theme/localizations.
Hosts do not need to add another bridge merely to use the package's own widgets.

## Runtime dependencies

- `flutter`: framework widgets, painting, gestures and services.
- `material_ui`: editor/viewer/picker UI and localization delegates. It owns its
  legitimate Cupertino/localization dependencies; the wrapper does not declare
  packages it never imports directly.
- `flutter_svg`: inline and network SVG backdrops in the public grid viewer.
- `flutter_colorpicker`: the editor color dialog. Keep its full interaction and
  accessibility behavior; a dependency cleanup must not remove that feature.
- `venue_layout_core`: shared geometry, scene compilation, SVG imports and text
  fingerprints. Its crypto, XML and SVG compiler packages are used directly.

The core allows compatible crypto updates. XML 6.6.1 and 7.x are
accepted below 8.0.0, subject to the selected SVG compiler's own compatibility
range. The SVG compiler stays at 1.3.0: `SvgGraphicImport.receipt.converter`
identifies that exact implementation. Relaxing it requires a separate truthful
provenance contract and output-compatibility proof, rather than returning an
incorrect version in existing receipts. Pub selects versions compatible with the actual SDK and the complete
host dependency graph. No `any` constraints, external version overrides, forks,
or exported alternate implementations are used.

## Reproduce the wrapper minimum

Use an isolated checkout so dependency resolution cannot disturb another task.
Keep only one Flutter task active at a time:

```sh
fvm install 3.44.0
fvm use 3.44.0 --force --skip-pub-get
python3 tool/configure_workspace.py
fvm flutter pub downgrade
fvm flutter analyze --no-pub
fvm flutter test --no-pub --concurrency=1
# Repeat with the newest versions compatible with this SDK.
fvm flutter pub upgrade
fvm flutter analyze --no-pub
# Flutter 3.44 can otherwise reuse old dependency shader assets.
rm -rf build/unit_test_assets
fvm flutter test --no-pub --concurrency=1
```

The generated local override selects the unpublished local core source only;
it never overrides crypto, XML, SVG compiler, UI versions or SDK constraints.
Published archives exclude it. Release validation must also retain the existing
clean archive consumer and publish the core before a wrapper release that needs
its new version. Changing an example's lockfile does not prove the wrapper's
minimum dependency set.

CI runs each graph in a fresh checkout. When switching graphs locally, remove
only `build/unit_test_assets` before testing: Flutter 3.44
`TestCommand._needsRebuild` does not notice newly added package shaders when
their timestamps predate the existing asset manifest. This is a test cache issue,
not a reason to exclude otherwise compatible UI releases.

When finished in a development checkout, restore the normal development SDK
with `fvm use 3.47.7 --force --skip-pub-get` and resolve dependencies again.
Never raise the public minimum merely because a newer SDK was used for development.
