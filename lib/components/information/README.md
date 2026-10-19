# Information, songbook and game boundaries

Ordinary information and songs can read previously synchronized content through
`OfflineDataService`, which delegates to Client Sync projections when selected.
A cached page does not make a game guess an offline operation.

`DbInformation.gameGuess` selects `game_guess_client_sync_v1` or the legacy
`game_guess` RPC. SQL validates guesses and membership; the client renders the
returned domain result. Keep guesses on that command boundary.

Answers live in `information_hidden`. Public participant projections must not
include them. Authorized editing does load hidden configuration, so "no client
can read answers" is not the security contract. Check both the editor boundary
and public/private projections when changing this data flow.

Song display uses the specialized `SongDialog` for its own reading theme,
font size and scrolling. Shared dialog/editor changes must preserve those
controls. Cache behavior is documented in
[Services](../../../docs/architecture/SERVICES.md).
