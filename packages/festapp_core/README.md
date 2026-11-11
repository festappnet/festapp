# Festapp portable client core

Production code and Dart tests use these same implementations. There is no
Flutter dependency, app import or IO implementation in this package.

| Entry point | Responsibility |
| --- | --- |
| `sync.dart` | Protocol, port-based storage/orchestration, HTTP and polling |
| `forms.dart` | Immutable definitions/options/capacity, metadata/defaults and registration read/error contracts |
| `eshop.dart` | Immutable product/catalog/account/report values and existing client projections |
| `program.dart` | Immutable events, explicit occasion time, relations, registration and saved-program coordination |
| `map.dart` | Place/path data, direction/style rules, GPX and offline manifest schema |

Allowed module edges are forms -> eshop and program -> map. `json_values.dart`
contains only recursive JSON ownership, used by four modules. No all-in-one
barrel or cross-module `src/` imports are allowed. SQL remains authoritative for
permissions, inventory, orders and payment states; these are client contracts.

App grid records own presentation and explicit commands. App editors own drafts
and replace snapshots/freeze them when committing. Form bundles attach occasion
and account context through an explicit `definition`. Event creation/decoding
requires `OccasionTimeContext`; product price evaluation receives a captured
clock value. Codecs preserve existing wire shapes and do not mutate source data.

```bash
fvm dart pub get
fvm dart analyze
fvm dart test
```

`automation/test_client.sh` is the complete repository gate, including native VM
and Flutter roots. Its architecture guard parses import/export/part/conditional
closures, production dependency graphs, module direction, test registration and
classification, registration-time effects and private SDK fixture imports. Direct `fvm flutter test` alone does not run this package.

### Payment selection and reservation presentation

`FormPaymentConfiguration` round-trips the canonical bank/cash/provider choice;
`FormPaymentOptions` consumes SQL availability and cash instructions. Builtin
method identities are shared in the payments module. Core does not infer a
method from missing bank data or compute deadline policy. Order payment
projections retain the server's method, financial facts, effective policy and
instructions; cash has no payment QR, while bank `none` keeps its bank QR.
The SQL and compatible reader/write contracts are documented in
[Forms](../../lib/components/forms/README.md#cash-reservations-and-deadline-policy)
and [Eshop](../../lib/components/eshop/README.md#cash-payments-and-payment-deadlines).
