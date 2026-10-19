# Festapp web client

The vanilla JavaScript client handles the public occasion catalog, forms,
checkout and browser ticket scanning. PostgreSQL owns business decisions shared
with Flutter; this client owns browser state and rendering.

## Run locally

Complete [developer setup](../docs/setup/howto.md) and apply the selected public
configuration from the repository root:

```bash
./automation/apply_config.sh
```

Then, inside `web_client/`:

```bash
npm ci
npm run dev
```

`src/app_config.js` and `src/theme_config.css` are generated. Put changes in
`automation/project.conf` and the generator inputs. Keep private credentials out
of browser assets. SQL tests use the [isolated local database](../docs/setup/local_development.md).

```bash
npm test
npm run build
```

The build above produces only this client. A tenant production release combines
it with Flutter through the [Pages release path](../automation/cloudflare/README.md).

## Browser state and domain boundaries

Page components use the `init()` / `render()` / `clear()` lifecycle from
`src/components/base/component.js`. Release page listeners and owned resources
on clear; small widgets have their own lifecycle.

Forms load `get_form_by_link` through `DbForms`. `FormModel` holds the loaded
bundle; `FormSession` tracks tickets, fields, currency and validation, and
`FormDataReader` creates the submission payload. Do not infer server capacity or
permissions from DOM state. Shared deletion, availability, waitlist and customer
capability rules live in the [form domain reference](../lib/components/forms/README.md).

`DbOrders` sends order create/replacement through `send-ticket-order`. The
receipted SQL command owns allocation and transactional effects. A queued
confirmation and a delivered email are different states. Keep the shared
[order contract](../lib/components/eshop/README.md) and
[email delivery boundary](../docs/setup/aws_ses.md) in sync with both clients.

Form typography inherits the generated tenant font/scale. A per-form Google
font override sets its scale to 1; removing the override restores inheritance.
Theme changes and input rendering belong to `ThemeService`, not order payloads.

## References for changes

- [Seat-map renderer](src/components/blueprint/README.md): transforms, gestures
  and cleanup specific to this DOM implementation
- [Browser scanner](../docs/runbooks/web-scanner.md): offline preparation,
  synchronization and recovery
- [Contributing](../CONTRIBUTING.md): test lanes, configuration and translation workflow
