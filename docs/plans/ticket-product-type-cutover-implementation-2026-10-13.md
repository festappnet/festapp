# Lokální implementace product type cutoveru

Verification: standard. Pracovní základ je `feat/occasion-setup-wizard-20261007`,
HEAD `eb23047248d59bf86345b9e0b79db4a988275231`. Cizí necommitované změny,
včetně souběžných úprav limitu objednávek a multi-selection, jsou zachované.
Nebyl proveden produkční zápis, deployment, commit ani push.

## Výsledek

SQL, Flutter a Edge přijímají schema 3. Produktové pole obsahuje konkrétní
`productTypeId` a vlastní popisek. Data, flow a warnings používají ID prvku.
Preview, download a příprava queued email PDF dosahují stejného rendereru.
Katalog obsahuje i skryté historické produkty. Výběr netřídí podle
`product_types.type`; prodejem skryté produkty na zakoupené vstupence zůstávají.

Picker nabízí skupiny použité alespoň v jednom formuláři dané akce, včetně
skrytých polí podle posledního upřesnění uživatele. Výběr/cancel, lokální filtr,
konkrétní názvy a příklady, vlastní/prázdný popisek, grouped undo, bezpečný nový
box, odstranění tiskového prvku a mobilní properties tab používají stávající
controller a Material UI. Escape zavře pouze picker. Dlouhý název i 320 px při
200% textu mají cílený test; mobilní tlačítko šablon má omezenou výšku.
Reset nového produktového textu používá obecný výchozí styl.

Resolve poskytuje jeden katalogový snapshot a normalizované příklady. Projekce
se cachuje podle identity dokumentu, scénáře a katalogové revize. Add/change/
remove/label/undo nevolají resolve ani PDF. Retry načte pouze catalog mode. Prázdný picker odkazuje do formulářů dané akce.
Symbol měny normalizuje server pro shodný canvas/PDF text; byte budget zahrnuje
i mezery serializace jsonb.
Setup draft má explicitně omezenou editaci produktových skupin; blank draft
nepřebírá produktová pole ani katalog půjčené zdrojové akce.

## SQL boundary a odstranění

- `ticket_layout.sql`: strukturální/context validace, limit 32 prvků, 32 KiB,
  JS-safe IDs, unikátní skupiny v template, trimovaný label, flow podle ID,
  odmítnutí legacy selektorů a null resetu. Expected layout/aggregate receipts
  zůstávají na existujícím command boundary.
- `update_occasion_internal_v1`: validuje reference při create/update.
- `duplicate_occasion_internal_v1`: remapuje oba slots přes úplnou temp ID mapu;
  chybějící mapování ruší celou kopii. Původní target-unit změny jsou zachované.
- `update_product`: přesun zakoupeného produktu do jiné skupiny je odmítnut;
  title/hidden edit zůstává funkční. Direct catalog DML je revokované.
- Skutečný delete caller je `delete_form_ws -> delete_form_client_sync_v1 ->
  delete_form_internal_v1`. Test vyvrátil předpoklad starého `delete_form.sql`;
  plán a canonical zdroje byly opraveny před pokračováním. Reference layoutu
  blokuje odstranění prázdné skupiny a celý neúspěšný command rollbackuje.
- `update_form_internal_v1` má stejný explicitní editor check jako jeho
  boundary. Interní write helpers nejsou přímo executable pro anon/authenticated.

Runtime `ticketTemplateImport.ts` a starý `import-layouts.ts` jsou odstraněné.
Frozen schema 1/2 reader/importer je pouze v offline tooling adresáři. Odstranění
nevyužitého řádku zachová jeho geometrický posun i dynamické skládání dalších polí. Presets
nepřidávají produkt automaticky. Nové prázdné schema-3 slots používají neutrální
preset; historické artwork konfigurace bez layoutu vyžadují migraci. Aplikované
historické SQL a doručené PDF baseline soubory zůstaly nedotčené.

## Ověření

[Strojová evidence](ticket-product-type-cutover-evidence-2026-10-13/local-verification.json)
obsahuje digests, scope a počty. Cílené Deno testy kontraktu/preview/migrace,
layout/PDF a fontů prošly. Flutter sada editoru a doplněné testy parity,
320 px/200%, Escape, label undo, safe placement, draft contextu a nulových
implicitních requestů prošly. Již prošlé nezměněné části se neopakovaly.
Dart analyze nemá chyby ani varování; ponechává style-level infos.

Tři SQL test files prošly v samostatně klonované lokální databázi. Testy pokrývají
reference jiné akce, nebezpečná ID, flow, legacy/reset rejection, autorizaci,
conflict/replay, title/hidden edit, historický reparent, rollback při cleanupu
referencované skupiny a atomický rollback kopie při neúplné mapě.

Lokální inventory/dry-run/apply/verify zahrnul tři konfigurace: schema 1, schema 2,
implicitní layout; oba slots; hidden/closed form; další nepoužitý food kandidát a
transport bez tiskového bindingu. Unresolved = 0. Readback souhlasí; druhý apply
nemění verze, audit ani ledger. Konflikt posledního řádku i drift katalogových
vazeb ruší celou transakci. Forward migration souhlasí se všemi osmi canonical
SQL zdroji. Nesouvisející pending migrations nebyly aplikované.

Import graph checker prošel 44 runtime modules z download, preview a email queue:
žádný legacy selector ani offline importer není dosažitelný. Scoped aktivní
SQL/Dart/TS schémata nemají food binding. Syntetický QR neposkytuje admission
credential. Browser smoke použil izolovaný local headless Chromium na skutečném
fixture editoru/Edge handleru: desktop 1400 x 1000 a mobil 320 x 800, dlouhý název,
filtr, Escape/cancel, potvrzení, přechod do vlastností, živý popisek a explicitní
PDF. Editace měla 0 preview requestů; explicitní PDF přesně 1 se schema 3 a
aktuálními oběma product IDs/popisky. Nezaznamenal JS chyby ani horizontal overflow.
Screenshoty jsou v `.codex-artifacts/ticket-product-type-cutover-2026-10-13/`.
Finální picker subset: 8 passing; offline migrace: 3 passing, včetně zachování
dynamické geometrie. Browser session a fixture server jsou zastavené, dočasná
databáze je odstraněná. Původní lokální databáze zůstala nedotčená.

## Přesné zbývající produkční kroky

1. Samostatně autorizovat publikaci, jeden tenant klienta a rozsah všech
   konzumentů sdíleného DB/Edge rendereru. Evidence dalších 11 organizací je
   skutečný blocker společného release; tento lokální celek je nemigroval.
2. Z canonical main připravit přesný klient/Edge bundle a ověřit activation,
   tenant organization, DB identity, SQL/bundle digests a zálohu. Scope migration
   ledgeru je pouze `20261013160000_ticket_product_type_cutover`.
3. Použít existující globální email gate: uložit původní `email_capacity.paused`,
   nastavit paused, nechat doběhnout sending/preparing leases a zastavit staré
   dotčené function instances. Gate pro rest writes/copy/render musí být schválený
   podle sdíleného scope. Existující runtime write-barrier skript je promotion
   nástroj omezený na timestamped DB; pro live cutover jej nelze použít naslepo.
   Konkrétní host/service fencing příkazy závisejí na schváleném live rozsahu.
4. Po zastavení zápisů obnovit `inventory.sql`, materializovat skutečné resources,
   vygenerovat úplný manifest/dry-run s 0 unresolved a reviewable apply SQL.
   Evidence organization 3 z plánování není apply manifest s aktuálními hashi.
5. Schválený apply SQL provede pouze tento forward SQL, všechny scoped layouty,
   audit, aggregate version, client-sync invalidaci a migration ledger v jedné
   transakci. Kontroluje features/version i form/historical catalog snapshot.
   Replay je no-op. Použít schválený canonical SQL transport; nepouštět globální
   `supabase migration up` nad dirty checkoutem.
6. Nasadit všechny dotčené shared Edge consumers (`preview-ticket-layout`,
   `download-ticket`, `process-email-queue` s jeho shared rendererem) a vybraný
   tenant klient, ověřit běžící digest, readback/refresh/snapshots a syntetické PDF.
   Ověřit queued ticket přípravu bez zákaznického rozesílání. Obnovit původní
   queue pause stav a writes/processing až po kontrolách. Nechat staré instances
   zastavené; po schema-3 editacích používat forward fix, ne legacy rollback.

Produkční resources, aktuální queue contents, live grant drift a deployed package
digest nebyly nově ověřované. Produkční readiness není zaměněná za dokončenou
lokální implementaci. Žádné jiné tenant branche nejsou v rollout scope.
