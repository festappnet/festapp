# Festapp cross_file 0.4 migration

Official stable file_picker release sources, with native platform implementations
unchanged. These seven packages are one coordinated port:

| Package | Upstream version | Official archive SHA-256 |
| --- | --- | --- |
| file_picker | 13.2.0 | `f201f3cbbb38ea5cd4e6896549662690f445a66261484f8ad697351c1ca25581` |
| file_picker_platform_interface | 4.2.0 | `336e7168306834a2b68e6168ed768e00d3fabeac23154d5793e277ca9f97cf20` |
| file_picker_web | 4.2.0 | `a2288008280aabe371aff029466b3405e60838e0a1d714767488c59b926c8b8c` |
| android_file_picker | 2.1.2 | `03d3dd3cb578ab26b1e528aeea27bf6b976942f5a24e3da82d270369b8e161a8` |
| file_picker_darwin | 2.4.0 | `13e731433fb3e59c1aff5a1197e41c5c5f930fad16342d101579086271a70d7b` |
| file_picker_linux | 2.0.0 | `e7db600f50672ce5ebbe422ac0906e0f3d2a476188cc93e7126afee12bf08063` |
| windows_file_picker | 2.0.1 | `18452aa293de3b6961c6d05b0e71b4be7bb90c67635abdd3aa5c4e75dd875072` |

Archives are `https://pub.dev/api/archives/<package>-<version>.tar.gz`.
Keep every upstream license and native source. Examples are omitted.

Changes:

- Require cross_file 0.4 and link the coordinated picker packages by relative
  path. Remove upstream monorepo workspace resolution for standalone use.
- Shared `pickedXFile` preserves picker names, cached bytes, UTF-8 decoding and
  independent range streams over the new PlatformXFile API. Native file URIs
  delegate to filesystem/scoped providers; browser URLs use the public web
  creation parameters. Byte-backed construction has no replacement in the new
  facade, so this picker adapter implements its typed platform interface.
- Five backend PlatformFile classes replace only their removed XFile constructor
  calls with that shared adapter. No Kotlin, Swift, Objective-C, C++ or native
  permission/window-management code is changed.
- Retain upstream tests; migrate their three XFile constructors and explicitly
  register IO/web providers in isolated tests. Add byte/name/range/error tests.

The application owns `ImportFile` at its upload/import boundary. It awaits reads
within onDrop; dialogs explicitly retain bytes before the provider expires and
await pending retention on confirmation. Imports explicitly request copy, never
move. Read errors remain errors, not empty files. Oversized image checks run
before loading content. Date/time parsing and stored application data are not
rewritten by this migration.

Verification commands (one Flutter task at a time):

- Root: targeted Flutter import/drop/auth suites recorded in
  `/tmp/festapp-crossfile-auth/`.
- `cd packages/file_picker_web` then `fvm flutter pub get` and
  `fvm flutter test --platform chrome --concurrency=1 test` for real DOM picker
  files/Blobs. Chrome is headless with an isolated temporary profile.
- Root native picker/interface test directories can be passed explicitly to
  `fvm flutter test --concurrency=1`.

Remove all seven copies and their root overrides together when official stable
picker packages support cross_file 0.4 and these contracts pass against them.
Do not replace this implementation with a constraint-only cross_file override.
