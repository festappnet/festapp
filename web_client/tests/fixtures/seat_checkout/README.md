# Selected-seat checkout regression

Run against the disposable local database bootstrapped by
`automation/bootstrap_local_db.sh`:

```sh
DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' \
  node web_client/scripts/run_db_tests.js required_ticket_spot_transport_test required_seat_checkout_test
SEAT_CHECKOUT_DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' \
  pnpm --dir web_client run test:seat-checkout-browser
```

The browser test requires locally installed `agent-browser` 0.33.1 and Chrome
(`agent-browser install`). CI runs both checks in `seat-checkout-regressions.yml`.

The browser physically clicks a rendered seat, closes the map, opens the order
preview and confirms the order. It asserts SQL reservation and the persisted
seat/order/ticket relationship as well as the rendered success screen. All data
lives in one local transaction which is rolled back. The owned Vite server and
isolated headless browser are closed afterward; outbound traffic is restricted
to loopback and email queue wake is scheduled.

FormPage, BlueprintSelector, renderer, FormSession, preview and DbOrders execute
unchanged. A small HTTP transport adapter substitutes for Supabase REST and the
Edge gateway, calling the real SQL RPCs with the `anon` database role. The
send-ticket-order adapter formats the SQL result for the real result renderer;
this check does not exercise Edge payment presentation, email delivery or
Fakturoid. Those boundaries retain their separate tests.

The transport contract is `ticket.spot`, distinct from ordinary
`ticket.fields` answers. Required-field validation checks presence; the existing
order finalizer owns seat occasion, reservation secret, occupancy, pricing and
allocation. Waiting registrations do not reserve seats. Both contract-level and
full anonymous checkout SQL regressions prevent this distinction from drifting.
