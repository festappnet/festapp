# Implementace předgenerovaných vstupenek pro ruční prodej

Pracuj v `/Users/miakh/source/festapp`. Přečti AGENTS.md, CLAUDE.md,
docs/architecture/ai_context.md a celý autoritativní návrh:

`docs/plans/pregenerated-manual-ticket-sales-plan-2026-10-23.md`

Plán byl přepracován proti současné SQL/Dart/Edge architektuře se subagentem
Astra. Implementuj vlny v pořadí s ověřováním standard. Použij jeho explicitní
produktové předpoklady, pokud nové zadání neurčí jinak. Zachovej cizí rozpracované
změny; změněné faktické předpoklady oprav v plánu s konkrétní evidencí.

Cíl: stock dávka se skutečnými eshop.tickets, vlastní panel, předprodejní stažení
a atomický ruční prodej za hotové. Zachovat ticket.id/symbol, opt.id, spot.id
A resource. Sdílej tvorbu nových produktových/ticket řádků s checkoutem, ale při
prodeji nevolej checkout finalizer ani apply_allocations. Nepřepisuj veřejný limit20.
Waitlist při sdílení produktové operace zachová existující ticket IDs.
Celá dávka má jediný sealed resource manifest před prvním renderem.
Prodej používá existující non-Stripe finance a manuální CASH pohyb, obě potřebná
práva, receipt a Client Sync; kontakt nesmí bez opt-in vyvolat e-mail.

Doplň nejen nové příkazy, ale všechny direct/indirect writer guardy, retained
scanning cesty, offline fingerprint, stock read přes get_orders/DbTickets,
report scopes/timeline a frozen download I email PDF. Nový privátní storage a
fenced bounded export jsou součást realizace. Fakturoid a nepodporované jmenné
flows odmítej podle plánu. Žádná druhá evidence QR, kopie platebního enginu,
p_stock bypass nebo neomezené base64 PDF. Nezaměňuj plánované RPC za existující.

Dokončení ověř podle akceptační matice včetně dvousession race a jednoho úplného
headless UI průchodu. Dodrž jedinou Flutter úlohu na stanici a --concurrency=1.
Runtime inventory regeneruj až s kódem a dodrž source-parity/forward migrace.
Bez samostatného zadání žádný commit, push, produkční migrace ani deploy.
Na konci stručně uveď výsledek, skutečné ověření a zbývající provozní kroky.
