# Publishing Venue Layout to npm

Venue Layout is the product name. Its JavaScript package is
`@festapp/venue-layout`; the Flutter package remains `venue_seat_picker`.
The `@festapp` scope is already used by `@festapp/banksync`.

## Release flow

The repository follows the BankSync publishing model: promotion from main,
immutable release tags, a protected `npm` environment and GitHub OIDC.
No local npm login or stored write token is needed for normal releases.

1. Increase the JavaScript version in `web/package.json` and merge the change.
2. Wait for CI on that exact main commit to pass.
3. Run the **Promote npm release** workflow with that JavaScript version.
4. Promotion creates the protected `npm-vVERSION` tag and dispatches `release.yml`.
5. The release selects the successful main CI run for the exact tagged commit
   and downloads its immutable archive from that run attempt. It does not rebuild
   passing Flutter/JS inputs. Its publishing job uses the `npm` environment review,
   then uploads the exact
   tested tarball through npm trusted publishing with provenance. The identical
   archive and its SHA-256 are attached to the GitHub release.

From the repository root:

```sh
NPM_RELEASE_VERSION=$(node -p "require('./web/package.json').version")
gh workflow run promote.yml --ref main -f version="$NPM_RELEASE_VERSION" --repo festappnet/venue_seat_picker
```

The wrapper's pub.dev version is independent of the JavaScript version; npm tags
therefore use `npm-v` instead of sharing an ambiguous `v` tag. Failed registry
lookups stop publication. A retry skips an existing version only when its npm
integrity matches the qualified tarball. A different gzip encoding is accepted
only when its full uncompressed tar payload is byte-identical; the original
registry bytes are retained under a distinct hash-named path for the GitHub
release. Changed package contents require a new version. CI artifacts expire
after 14 days; promote a passing build within that window.

## Configured publisher

The first public `@festapp/venue-layout@0.3.5` publication was bootstrapped from
the qualified source archive on 24 October 2026. Its registry tarball was checked
byte-for-byte against that archive. The package's GitHub trusted publisher is
configured with:

- Organization: `festappnet`
- Repository: `venue_seat_picker`
- Workflow filename: `release.yml`
- Environment: `npm`
- Allowed action: direct `npm publish`

The GitHub side uses immutable `npm-v*` tags and the same npm environment reviewer
as BankSync. There is no alternate publishing job in CI and no activation flag.

BankSync's trust is package-specific and was not reused as an authorization for
Venue Layout. See [npm trusted publishing](https://docs.npmjs.com/trusted-publishers/)
and [npm trust](https://docs.npmjs.com/cli/v11/commands/npm-trust/) if this binding
needs to be restored. Normal releases use OIDC and do not need another local login.
Pub.dev releases and Festapp's verified source-archive integration are independent.
