# Occasion Component

**Purpose**: The Core definition of an "Event" (Occasion). Manages settings,
services, and lifecycle (Duplication/Deletion).

## Core Concepts

### 1. Services (`ServiceItemModel`)

- **Purpose**: Manages "sub-services" like Food or Accommodation available at
  the event.
- **Logic**: Simple CRUD via RPCs (`create_service_item`,
  `update_service_item`).

### 2. Game Settings

- **Purpose**: Manages the "Game" feature enabled for an occasion.
- **Storage**: Stored inside the `data` JSONb column of the `occasions` table.
- **RPC**: `game_update_settings`.

## Complex Flows

### 1. Duplication (`duplicateOccasion`)

**Hybrid Logic**:

1. **SQL**: Calls `duplicate_occasion_client_sync_v1` (or the
   `duplicate_occasion` facade) to copy the database row and related tables.
   The optional target Unit defaults to the source. The caller must manage
   both Units within the same Organization (tenant). `get_occasion_copy_units`
   supplies authorized destinations for the confirmation dialog.
   Email overrides retain their content and title with the target ancestry;
   inherited templates and wrappers resolve through the target Unit. Places
   and information also move to the target. A form's bank account is retained
   across Units only if linked to the target; otherwise the account is cleared
   and that form is closed for review. Receipts and catalog updates belong to
   the target Unit, and the creator receives occasion administration rights.
2. **Shared media completion**: `start_occasion_lifecycle` attaches one durable
   media job to that receipt. `OccasionDuplicator` and MCP both resume the job
   through `/occasion-lifecycle` in the canonical image Worker. Deterministic
   object keys and registered steps preserve identity after lost responses.
   The Worker copies each distinct ticket/occasion image, preserves bundled
   presets, and SQL applies only references the user has not changed meanwhile.
   Dart retains its media intent until completion, including across restart;
   a retry never allocates another database copy for unfinished media.

### 2. Deletion (`deleteOccasion`)

`DbOccasions.deleteOccasion` calls the Client Sync delete command when v1 is
selected, otherwise the `delete_occasion` RPC. SQL owns record deletion. There
is no client-side orphan-image scan or Supabase Storage cleanup in this flow.

## Critical Implementation Details

- **Hybrid Operations**: Unlike pure SQL features, Occasion management often
  involves significant Dart-side orchestration, especially for **Files/Images**.
  Do not assume the SQL RPC does everything (it doesn't copy the binary files).

## Public URL ownership

SQL `public_links/registry.sql` owns current and historical public slugs. New
items with a blank slug receive an independent cryptographic 8-character code.
Explicit changes use lowercase ASCII letters/digits and single hyphens, up to
80 characters; unchanged legacy links are retained exactly. Domain commands
reserve URLs atomically with writes and receipts. Reservations survive deletion
as tombstones. Aliases resolve to stable IDs under the existing permissions.

Settings keep a separate server-confirmed link baseline: Copy uses the saved
public URL, while an unsaved proposal is plain text. Loaded aliases replace the
URL without adding history or discarding query/capability fragments. Unknown
aliases require an online resolve. Occasion copy locale is captured once and
persisted in the command/draft; SQL alone owns the localized copy title.

Existing cross-tenant occasion duplicates keep frozen tenant-scoped ID bindings.
New writes cannot claim those slugs; canonical links and titles are never bulk renamed.
