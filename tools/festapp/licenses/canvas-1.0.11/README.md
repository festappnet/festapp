# @napi-rs/canvas 1.0.11 notices and source

This distribution uses the FreeType Project (https://www.freetype.org/).

The files here accompany `@napi-rs/canvas` and `@napi-rs/canvas-linux-x64-gnu` 1.0.11. `canvas-LICENSE`, `skia-LICENSE`, `skia-vendored/`, and `crates/` preserve the upstream license and notice texts; `provenance.json` identifies their source and `sbom-linux-x64-gnu.cdx.json` records the native package's published inventory. Some inventory components may be build-time or platform-specific. Keep these notices with the binary distribution.

The complete published source files for the following MPL-2.0 crates are in `mpl-source/`, unchanged from the published crates.io archives. Their archive SHA-256 values agree with the canvas 1.0.11 release Cargo.lock:

| Source | SHA-256 |
| --- | --- |
| [cssparser 0.38.0](https://static.crates.io/crates/cssparser/cssparser-0.38.0.crate) | `11119743ad110e8c1bdccd930d7f5c30c99e5fc76a7b63ec9807e84eef0c5f59` |
| [cssparser-color 0.6.0](https://static.crates.io/crates/cssparser-color/cssparser-color-0.6.0.crate) | `cc0e59e8bcc238f0f9b9f29f4d649e5c192dbf277999d0c23d1a312af3fb7a3e` |
| [cssparser-macros 0.7.0](https://static.crates.io/crates/cssparser-macros/cssparser-macros-0.7.0.crate) | `10a2a99df6e410a8ff4245aa2006499ea662245f967cc7c0a38c83ef8eb44dbf` |
| [dtoa-short 0.3.5](https://static.crates.io/crates/dtoa-short/dtoa-short-0.3.5.crate) | `cd1511a7b6a56299bd043a9c167a6d2bfb37bf84a6dfceaba651168adfb43c87` |

The [release Cargo.lock](https://github.com/Brooooooklyn/canvas/blob/v1.0.11/Cargo.lock) identifies all four as crates.io registry sources, and [Cargo.toml](https://github.com/Brooooooklyn/canvas/blob/v1.0.11/Cargo.toml) has no patch section. This establishes the released source inputs and no declared Cargo patch; it does not independently reproduce the shipped binary. Preserve the MPL license and source materials in distributions that include the executable.
