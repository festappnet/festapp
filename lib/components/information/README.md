# Information Component

**Purpose**: A CMS (Content Management System) for static pages AND the "Game"
logic.

## Core Concepts

### 1. CMS Pages (`InformationModel`)

- **Type**: Standard info pages.
- **Offline**: Content is cached via `OfflineDataService`.

### 2. The Game (`game_guess`)

If `type == "game"`, the page becomes a game checkpoint.

- **RPC**: `game_guess`
  (`database/functions/others/game_guess.sql`)
- **Logic**:
  - Users enter a code/password.
  - SQL validates it against the hidden answer.
  - Returns specific error codes (4031: Not in occasion, 4001: Wrong answer).
  - **Anti-Cheat**: Logic is entirely server-side to prevent inspecting the app
    for answers.

### 3. Songbook Mode (`type == "song"`)

A specialized view for song lyrics and chords.

- **Location**: `lib/components/information/song/`
- **Offline**: Heavily relies on `OfflineDataService` so it works at campfires
  without signal.
- **UI**: Features a dedicated **Dark Mode** toggle and font-size scalers
  (`SongDialog`) independent of the main app theme.

## Critical Implementation Details

- **Hidden Data**: Game answers are stored in `information_hidden` table, _not_
  sent to the client. Only the `game_guess` RPC can access them.
