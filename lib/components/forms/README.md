# Forms (Dynamic Data Collection & Ticket Ordering)

## The Form Bundle (CRITICAL)

Forms are NOT simple definitions. `get_form_by_link` RPC returns a massive bundle:
- Form metadata + field definitions
- Products with dynamic availability (checked via `is_product_dynamically_available` SQL)
- Session `secret` UUID for spot locking

If a product isn't showing, check `is_product_dynamically_available` in SQL, not Dart.

## Gotchas

- **Never hardcode field IDs**. Find fields by `type` or `data` attributes -- IDs are generated.
- **Two submit paths**: Registration -> `create_form_ws` RPC. Ticket orders -> `send-ticket-order` Edge Function.
- **`widgets_view/`** = runtime (user-facing). **`widgets_editor/`** = design-time (admin drag-and-drop). Don't mix them.

## Rendering Engine

`FormPage` calls `DbForms.getFormFromLink`, iterates `form.fields`, selects widget by `field.type`, collects data into `FormHolder`.

## SQL RPCs

- `get_form_by_link` -- complete form bundle for user rendering (includes session secret)
- `get_form_for_edit` -- form + fields + products + bank accounts for admin
- `create_form_ws` -- creates form / submits registration
- `update_form` -- updates form metadata
- `duplicate_form_to_occasion` -- copies form to target occasion
- `get_blueprint` -- loads blueprint seat map for form session

## Editor deletion

`get_form_for_edit` returns `can_delete` and `delete_blocked_reason` for each
field/product. Missing usage metadata keeps saved items non-deletable. The
editor stages explicit `deleted_field_ids` / `deleted_product_ids`; only the
existing form-save command applies them in `update_form_internal_v1`. Partial
settings saves never infer deletion from omitted fields.

Save checks current answers and current order products (including cancelled
orders), blueprint spots, inventory links, and shared product groups. Removing
a ticket container includes its nested fields; removing a product field also
removes its unused products. The form row lock coordinates save with order
creation and response editing; product/type locks protect concurrent FK links.
Historical snapshots alone do not block deletion; order history remains intact.
A rejected save rolls back every change and leaves the editor draft intact.

## Editor draft actions

The form, settings, and design tabs use `EditorActionBar`: Save and Discard
changes are disabled until editable values differ from the loaded baseline.
Discard confirms, reloads the tab, and never pops the administration route or
invokes its close callback. Model snapshots include nested fields, products,
and staged deletions. Child editors report changes to refresh the action bar;
plain text fields also use the surrounding Form's change callback. HTML drafts
that are still open are included via `HtmlSaveCoordinator.hasActiveDraft`.
Keep model getters free of writes so rendering defaults does not create edits.
