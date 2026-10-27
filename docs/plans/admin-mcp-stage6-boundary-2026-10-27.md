# Stage 6 - people, roles and group boundary

Base: `origin/main` a698f7403. Isolated branch `feat/admin-mcp-stage6-20261027`.
Verification: standard. No production writes, deployment, provider call or tenant changes.

| Operation | Live SQL predicate | Canonical owner | Current UI producer | MCP operation |
| --- | --- | --- | --- | --- |
| Bounded participant page/inspection | `can_manage_occasion_participants` | `manage_people` bounded projection | Occasion user grid retains its existing larger editor bundle | `profiles.list`, `profiles.inspect` |
| Create/ordinary profile edit | `can_manage_occasion_participants` | `create_occasion_user_client_sync_v1`, `save_profile_client_sync_v1` | `SupabaseProfileCommands` | `profiles.create`, `profiles.save` |
| Explicit occasion roles, approval and volunteer status | `can_manage_occasion_participants` | Same `save_profile_client_sync_v1`, separate named `roleChange` intent | Profile grid uses the existing full editor aggregate | `profiles.roles` |
| Remove occasion membership | `can_manage_occasion_participants` | `delete_occasion_user_client_sync_v1` | `SupabaseProfileCommands.delete` | `profiles.delete` |
| Import ordinary participant rows | Current participant manager AND existing `get_can_manage_occasion_users` | `import_profiles_client_sync_v1` | `SupabaseProfileCommands.importProfiles` | `profiles.import` |
| Import ticket memberships | Current participant manager AND existing occasion editor permission | `import_users_from_tickets_client_sync_v1` | `SupabaseProfileCommands.importFromTickets` | `profiles.importTickets` |
| Bounded group page / complete inspection | `can_read_groups_editor` / `can_read_group_editor` | Existing group data owner, narrow projection | Existing group editor bundle | `groups.list`, `groups.inspect` |
| Group create/save/delete | `can_write_group` / `can_delete_group` | Existing group command owners | `SupabaseGroupCommands` | `groups.save`, `groups.delete` |
| Add members / replace assignments | `can_add_group_members` / `can_import_group_assignments` | Existing atomic membership commands | `SupabaseGroupCommands` | `groups.addMembers`, `groups.replaceAssignments` |
| Organizer members / ordinary fields / roles | `can_manage_unit_users`, whole-organizer consent | `save_unit_user_client_sync_v1` wraps existing `update_unit_user_internal_v1` | `SupabaseUnitCommands.saveUser`, grid retains original version | `units.people.list`, `units.people.create`, `units.people.profile`, `units.people.roles` |
| Organizer access removal | `can_manage_unit_users`, whole-organizer consent | `delete_unit_user_client_sync_v1` | `SupabaseUnitCommands.deleteUserAccess` | `units.people.revoke` |

Named profile patches are merged after original intent hashing, receipt replay and
version comparison inside the existing profile owner. Omitted fields, services and
roles survive. The shared JSON contract drives strict MCP schemas and the SQL named
patch validator. Role/volunteer changes require separate new scopes. Older grants
never gain these operations. No Node role expressions, second profile writer,
receipt ledger, ACL table or application trigger is introduced.

The organizer grid's direct `update_unit_user` producer is replaced by a versioned
command. The released RPC remains a facade into that command and acquires its
baseline under the same organizer lock. Existing profile/group editor aggregates
remain supported, rather than splitting one confirmed UI save into several writes.
Private group-map geometry stays with its existing editor owner; MCP edits shared
place references and complete memberships up to 500 people. Imports are bounded to
100 ordinary rows; no arbitrary metadata, roles, bulk deletes or email delivery.
Participant authoring deliberately requires manager rights even if an existing
read-only editor bundle permits a broader read role.

Stored occasion/unit bindings and live authorization facts are locked before
permission checks and receipt replay. Group inspection rechecks the group predicate
after acquiring the group lock. Profile/group current command callers share the
same scope fence; organizer save/revoke share one organizer lock. Self-revocation
may return its own successful receipt, then subsequent calls and replay fail using
live ordinary rights. No scope or role authority is cached in the MCP process.

Checks: actual authenticated PostgreSQL identities, frozen replay and conflict,
foreign-scope rejection, role and ordinary-data separation, all-or-nothing group
membership, revocation/read races with a real row-lock wait, SDK transport,
existing SQL group/profile regressions and targeted Flutter command/grid cases.
