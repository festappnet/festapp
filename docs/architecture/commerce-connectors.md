# E-shopové konektory - společná architektura Festappu

Historický výzkum a návrh z 29. 10. 2026, začleněný 6. 11. 2026. Nejde o implementaci ani novou autorizaci realizace. Tehdejší záznamy o neodeslání jsou překonané [stavem potvrzeným vlastníkem 1. 11.](../plans/shoptet-partner-onboarding-2026-10-26.md): návrh byl odeslán, čeká se na odpověď a další podání se neposílá.

Datum: 29. 10. 2026. Stav: **schválený směr, první rozsah a pořadí ověřování**. Vlastník potvrdil společné jádro s adaptéry, ověření Shoptetu před větší implementací, držení kapacity do vyjasnění a základní rozsah CZK/jedna akce včetně sedadel. Schválení těchto rozhodnutí není důkazem splnění provider garancí. Dokument není tvrzením, že Shoptet konektor již existuje. Referenční checkout: `00f05276de8c07c186c9d884e59291666d7707d6`; práce v `festapp-shoptet-research-20261029`. Ověřování: standard.

Tento dokument vlastní cílové chování, doménu a interface. [Realizační plán](../plans/commerce-connectors-plan-2026-10-29.md) vlastní pořadí změn a ověření. [Výzkum](../plans/shoptet-direction-plan-2026-10-29.md) a [veřejný kód](../plans/shoptet-self-verification-2026-10-29.md) jsou důkazy a historie rozhodnutí. Není autorizováno odesílání zpráv/podání, produkční změna ani placený pokus.

[Záznam schválených rozhodnutí](../plans/commerce-connectors-review-2026-10-29.md).

## 0. Rozhodnutí o společném konektoru

Vlastník požaduje stejný kontrakt i pro další e-shopové extensiony. **Jedno společné jádro Commerce Connector; Shoptet je první adaptér.** Nový e-shop, který splní stejný kontrakt, se připojí registrací adaptéru a manifestu, ne kopírováním objednávek, rezervací nebo pracovní fronty. Pokud přinese skutečně nový obchodní model nebo potřebné garance nemá, vyžaduje to explicitní změnu společného profilu; samotný adapter ji nemůže schovat.

Tento dokument je autorita společného jádra. [Shoptet adaptér](shoptet.md) vlastní pouze překlad provider kontraktu a konkrétní neověřené podmínky. Příklady Shoptetu níže označují první implementaci, nejsou univerzálními schopnostmi všech e-shopů. Další kandidáti včetně Upgates musí nejprve projít stejným profilem schopností; jejich API zde není vydáváno za ověřené.

### Co už zůstává kanonické

- Inventory SQL vlastní alokaci všech kanálů, včetně nových generic `capacity_reservations`.
- Existující order/ticket SQL a Client Sync vlastní obchodní identity, změny a effect receipts.
- `payment_financial_totals_internal` vlastní jednotnou projekci; konektor pouze přinese validované externí facts.
- `enqueue_paid_order_tickets` a stávající email_messages vlastní doručení. Integrace neodesílá jinou cestou.
- `tools/festapp/Operations` a Make zůstávají existujícími konzumenty kanonického backendu. Automatický provider callback se nepřevléká za lidskou MCP operaci orders.mark_paid.

Současné WordPress/Wix embedy jsou prezentační konektory: používají náš checkout. Make/MCP jsou automatizační konektory. Nativní e-shopový konektor přináší cizí objednávku/platbu. Sdílí doménové vlastníky, ale nedostane se mu obchodní správnosti tím, že všechny tři rodiny násilně převedeme na jednu HTTP obálku. Jejich přepis není součástí práce.

### Fyzický tvar a jediný interface

| Místo | Jediná odpovědnost |
| --- | --- |
| `integrations/<platform>/` | Manifest, tenký browser provider bridge a distribuce doplňku; setup, fixture a evidence. Doménová pravidla ani kopie výběru sedadel se sem nekopírují. |
| `web_client/src/components/eshop/commerce_checkout_session.js` | Společná klientská session/status/conflict pro nativní e-shopové extensiony; provider bridge dodá ověřitelný košík a převezme výsledek, ne obchodní logiku. |
| `supabase/functions/_shared/commerce/connector.ts` | Společný orchestration interface prepare/status/release/event/reconcile. |
| `supabase/functions/_shared/commerce/contract.ts` | Jedna deklarace normalizovaných snapshotů, outcomes a validací; backend i adapter tests ji importují. Browser DTO se odvodí z allowlist projekce, ne kopie raw provider schématu. |
| `supabase/functions/_shared/commerce/providers/<platform>.ts` | Konkrétní HTTP/auth/signature překlad; žádný vlastní sklad ani pricing výpočet. |
| `supabase/functions/commerce-connector/index.ts` | Jeden routovaný vstup, který validuje konkrétní route/auth mode a volá společný modul. Provider se dispatchuje ze statického registru, ne z uživatelského URL/importu. |
| `database/functions/commerce_connectors/` | Explicitní SQL operace nad generic commerce agregáty; service-only ingest oddělený od běžného uživatelského commandu. |
| `database/functions/inventory/` | Generic occupancy/admission/transfer capacity reservation. Žádná podmínka typu provider=shoptet uvnitř výpočtu kapacity. |

Worker používá stejný modul a generic commerce_tasks. Jeho neveřejný tick běží přes již schválený service worker mechanismus a musí dostat explicitní runtime instalaci; nevzniká veřejný neautentizovaný cron. Jedna fronta pro konektorové tasky, stávající samostatná doménová fronta pro e-maily se nemění.

### Společné nastavení a klientská zkušenost

Pořadatel spravuje připojení a mapování uvnitř stávající administrace Festappu, u akce/formuláře. Není druhá Shoptet administrační aplikace s jinou evidencí akcí. UI pracuje s generic installation/mapping/status DTO a kanonickými capabilities; label/icon providera je metadata. Secrets ani mapování se neukládají jako libovolný veřejný forms.data blob. Změny mapování jdou explicitním typed commandem.

Stejný výběr plánku používá existující renderer a blueprint layout/projekce. Pro nový commerce režim se připojí command callback do společné commerce session; nekopírovat plánek, jeho geometrii ani FormSession v každém extensionu. Stávající BlueprintLayoutAdapter předpokládá FormSession a jeho selectSpot cestu, proto se má vyjmout jen skutečná selection seam, ne volat starý veřejný checkout a pak skrýt jeho platební tlačítko. Přímý formulář zachová své dosavadní interface.

Každý platformní bridge vlastní pouze bootstrap košíku, vendor-specific popup/events a bezpečné předání výsledku do nativního checkoutu. Čekání, konflikt, reload, revision a odvozené ceny se zpracují ve společné klientské session. Pro Shoptet se renderer může zobrazit ve schváleném popupu; jiná platforma nemusí mít stejnou DOM strukturu. Změna wrapperu nemění serverový kontrakt.

Tabulky persistence níže jsou interní záznamy jednoho modulu, nikoli samostatné veřejné aplikace. Worker, ingress a browser nepíšou tabulky každý vlastní logikou; všechny obchodní přechody vlastní explicitní SQL operace.

### Provider interface a normalizovaný kontrakt

Každý adaptér implementuje `readCart`, `publishAuthorization`, `observeAuthorization`, `readOrder` a `verifyEvent`. Volitelná `revokeAuthorization` je dostupná jen profilu s doloženou nevratnou revokací; jádro ji nenahrazuje browserovou invalidací.

- CartSnapshot: verified installation, opaque checkoutRef, providerRevision nebo explicitní unknown, currency a lineKeys s SKU/variantou/množstvím. Nedodává-li provider stabilní lineKey, adaptér to označí; společné jádro nesmí předstírat stabilitu podle indexu pole.
- AuthorizationRequest: immutable offerId/revision, cartDigest, selectionDigest a expiresAt. Adaptér přeloží jen providerem podporovaná pole, neslibuje automatické serverové vázání našeho digestu.
- PublishOutcome: confirmed s providerRef/evidence, rejected s doloženým neprovedením, nebo unknown. HTTP úspěch s neodpovídajícím tělem není confirmed.
- AuthorizationObservation: acceptedOrder s orderRef, pending, nebo provenUnusable s konkrétní terminal evidence. Stav cancelled/404 se nesmí normalizovat na provenUnusable bez doložené provider sémantiky.
- OrderSnapshot: stabilní orderRef a položky, neměnné cenové údaje, podporovaný finanční důkaz a provider revision/observedAt. Snapshot není automaticky nová finanční transakce.
- VerifiedEvent: ověřená instalační/generační identita, event kind, entityRef a payloadDigest. Normalizace neuděluje právo ke cizí akci.

`shippingRequestCode`, `shippingGuid`, `verificationCode` a `atypicalShipping` zůstávají v adaptéru a jeho chráněném provider metadata. Jádro má checkoutRef, authorizationRef a contractProfile. U dalšího e-shopu se nevyrábí nová varianta této state machine.

### Manifest schopností místo rozvětvené business logiky

Každá instalace má provider/app identity a verzovaný `contractProfile=shared-reservation-v1`. Profil vyžaduje doložené vlastnosti G1-G5. Záznam každé vlastnosti rozlišuje unknown/documented/sandbox-observed a reference důkazu; samotný boolean z manifestu neopravňuje k aktivaci. Při změně provider kontraktu nebo ztrátě garance se zastaví nové nabídky a chrání existující claims.

V tomto rozsahu se implementuje jen shared-reservation-v1. Kvóty nebo externí přesměrování nejsou skryté fallbacky a nedostanou vlastní běžící větev. Budoucí rozšíření má explicitní nový kontrakt a rozhodnutí, nikoli podmínky roztroušené v checkoutu.

## 1. Výsledek pro kupujícího a pořadatele

Pořadatel připraví akci, produkty a plánek ve Festappu a namapuje existující produkty e-shopu; prvním adaptérem je Shoptet. Kupující zvolí vstupenky v Shoptetu, dokončí jeho nativní košík a platbu. Festapp spravuje společnou kapacitu, vydá existujícím mechanismem vstupenku a odešle ji kanonickou frontou. Stejná kapacita zůstává použitelná i přímým formulářem nebo jeho embedem.

První provozní profil: CZ/CZK, jedna akce a jeden formát mapování na košík, plná úhrada podporovanou metodou. Více akcí, měn, zálohy, dobírka a libovolný smíšený fyzický košík nejsou implicitně podporované. Omezení se musí ověřovat serverově při nabídce i přijetí. Smíšený košík je blokovaný do prokázání kompatibility doručení; pouhý JS zákaz nestačí. Pokud platforma neumí omezení bezpečně vynutit, tento profil není připraven pro pilot.

Běžné vstupenky a sedadla mají stejný stavový protokol. První sandboxový průchod může použít obyčejnou kapacitu, ale cílový návrh zahrnuje i konkrétní sedadla a atomické skupiny míst. Nevzniká zvláštní provizorní checkout.

## 2. Ověřená fakta a podmínky platformy

Veřejná dokumentace popisuje zvlášť schvalovaný shipping-addon kontrakt: serverově uloženou nabídku, verificationCode a expiraci kontrolovanou při objednání. Uvádí i digitální doručení a stavové čtení při ztrátě webhooku. [Zdroj](https://developers.shoptet.com/shipping-addons/). Strojové schéma potvrzuje GET/PUT cesty s shippingRequestCode a shippingGuid. [Důkaz](../plans/shoptet-direction-evidence-2026-10-29/public-contract.json).

Vstupenky lze jako kandidátní konfiguraci označit atypickou dopravou a k ní přiřadit naše digitální doručení. Nastavení musí projít backendovým testem obcházení. [Produkty](https://podpora.shoptet.cz/produkty-zaklady/), [dopravy](https://podpora.shoptet.cz/dopravy/).

| Brána | Co musí být prokázáno | Bez výsledku |
| --- | --- | --- |
| G1. Zpřístupnění | Vlastní instalace smí použít shipping-request pro ticketing/digitální doručení. | Jen lokální návrh a fake-provider experiment, žádný živý callback. |
| G2. Vynucení | Aktuální vstupenkové položky nelze zákaznicky závazně objednat bez správné nabídky; jiná doprava a změněný košík ji neobejdou. | Žádný pilot ani příslib bezpečného prodeje. |
| G3. Identita nabídky | Víme, jak server rozliší starý kód, aktuální obsah, opakovaný PUT a dvě okna. | Pozastavit změny nabídky, držet všechny nejisté alokace. Nedostatečné G3 nelze vyléčit jen lokálním revision číslem. |
| G4. Finalita | Víme, který stav dokládá, že konkrétní nabídka už nemůže být přijata. Samotný open, cancelled, 404 nebo čas nestačí bez tohoto kontraktu. | Kapacita zůstává blokovaná pro reconciliation; nelze slíbit automatické uvolnění. |
| G5. Finance | Jsou určené významy finančních polí pro konkrétní metodu, ruční paid a refundace. | Přijatá objednávka drží kapacitu, ale QR se nevydá podle nejasného finančního údaje. |

G1 je část běžného onboardingu. G2-G5 přednostně ověříme sami scénáři S1-S10; neznamenají automatické zprávy podpoře. Pozorované úspěšné testy jsou důkaz pro konkrétní verzi, ne důkaz všech budoucích souběhů.

## 3. Vlastníci a moduly

| Modul / vlastník | Vlastní | Nevlastní |
| --- | --- | --- |
| Shoptet | Košík, závazné přijetí externí objednávky, její ceny a dostupné platební údaje. | Naše společná místa ani generátor QR. |
| Commerce Connector | Jednotný interface pro přípravu nabídky, přijetí důkazů a reconciliation; řídí externí protokol. | Vlastní paralelní sklad, vlastní tickets nebo poštovní frontu. |
| Inventory SQL | Obsazenost všech prodejních cest, atomické skupiny sedadel, kapacitní pravidla. | HTTP, košíkovou session nebo odhad placeno. |
| Kanonické objednávky a finance | Order/ticket identity, převzetí již držené kapacity, finanční projekce. | Význam raw provider payloadu bez validovaného adaptéru. |
| Kanonické doručování | Effect intent, PDF/QR a existující frontu e-mailů. | Další implementaci odesílání jen pro Shoptet. |
| Browser widget | Výběr, zobrazení stavu a konfliktu, předání serverově ověřitelného košíku. | Důvěryhodnou dostupnost, cenu, oprávnění nebo potvrzení platby. |

Navržené místo modulu: `integrations/<platform>/` pro source, protokol a fixture; `supabase/functions/_shared/commerce/connector.ts` pro serverovou koordinaci a `providers/<platform>.ts` pro konkrétní HTTP adaptér. Browserový widget importuje pouze klientský transport, nikdy serverový provider nebo token. SQL zůstává kanonické v `database/functions/`.

Provider interface je definovaný v §0. Shoptet adaptér mapuje publishAuthorization na PUT nabídky a observeAuthorization na GET stavu. Změna dalšího adaptéru se nesmí projevit v Inventory SQL nebo v generátoru vstupenek.

## 4. Pojmy a stabilní identity

| Pojem | Identita a význam |
| --- | --- |
| Instalace | Interní UUID; stabilní provider/app identity + ověřené externalAccountRef; při reinstalaci roste credential generation. Tenant/unit se váže ověřenou administrátorskou operací. |
| Mapování | `(installation, productGuid, variantCode)` na occasion, form a product/blueprint binding; monotónní revision. Aktivní nabídka drží neměnný snapshot. |
| Checkout | `(provider, appIdentity, externalAccountRef, checkoutRef)`. Opaque string, ne e-mail. Interní UUID je veřejný identifikátor jen spolu s oprávněním. |
| Nabídka | Interní UUID + monotónní revision a payload digest; má providerMethodRef a vlastní external attempt. Každý pokus zachová neměnná vstupní data. |
| Rezervace | Interní UUID a immutable reservation items. Drží skutečné kanonické inventory units i limity produktu/formuláře. |
| Externí objednávka | `(provider, appIdentity, externalAccountRef, externalOrderRef)`; code je neprůhledný string. Generace přihlášení není součást business klíče. |
| Položka prodeje | Stabilní externí line ID, je-li doložené. Jinak výslovně zvolená identita při přijetí a zmrazený snapshot; nepoužívat index pole měnící se při editaci. |
| Finanční fakt | TransactionId + typ/revize, nebo řízený snapshot, pokud metoda nedává pohybovou identitu. Dva různé účetní modely nesčítat. |

Shodný e-mail neprokazuje stejný košík. Dva různé košíky mohou patřit stejnému člověku. Dvě záložky jednoho košíku mají sdílený serverový stav. Reinstall neobnovuje starou autoritu ani nevytváří nové obchodní identity.

## 5. Persistence - navržené tabulky

Názvy níže jsou cílový návrh, nic z toho zatím není migrované. Všechny FK scope vazby ověřuje SQL; žádný tenant/order z raw requestu není důvěryhodný.

| Objekt | Nezbytná data a omezení |
| --- | --- |
| `public.commerce_installations` | app/eshop identity, organization/unit, credential generation, canonical shop origin, health, activation state; unikátní app+eshop. Secret jen jako odkaz do chráněného úložiště, ne v browseru/logu. |
| `public.commerce_product_links` | install/productGuid/variantCode, occasion/form/product/binding, currency, revision a enabled; mapování nelze měnit pod aktivní nabídkou bez jejího bezpečného vypořádání. |
| `public.commerce_checkouts` | stabilní klíč, current revision, current offer, authorization generation, server session reference, reconcile status a error code; bez duplicitního košíkového ceníku. |
| `public.commerce_offers` | checkout/revision, providerMethodRef, cart digest, selection digest, mapping snapshot, expiresAt, provider state, authorizationRef šifrovaně nebo chráněně, reservationId; nabídka má auditní historii. |
| `public.capacity_reservations` | opaque ownerKind/ownerRef, disposition, scope, timestamps a terminalEvidence reference. Generic inventory neodkazuje FK na commerce checkout/offer; vazbu k rezervaci vlastní commerce_offers.reservationId. Počty jsou odvozené z immutable reservation items, nikoli druhé ručně udržované čítače. Expirace nabídky není permission k uvolnění. |
| `public.capacity_reservation_items` | interní intended-ticket key, form/product a požadovaná množství/atomické seat bindings; vyjádří spotřebu product maximum a participant capacity bez násobení podle počtu kontextů. Provider ceny, měny a mapping snapshot patří do commerce nabídky a order linku, ne do generic inventory. |
| `public.commerce_order_links` | external order code a line identity na kanonické orders/tickets; unique business klíč; snapshot jednotlivých cen po slevách a změnová revize. |
| `public.commerce_inbox` | ověřené raw-event digest, event identity, key generation, receivedAt a processing status; raw PII v omezeném retenčním úložišti. Deduplikace inboxu nenahrazuje business idempotenci. |
| `public.commerce_attempts` | immutable body digest, attempt UUID, fence, claimedAt, výsledná klasifikace a bounded evidence; jeden nerozhodnutý mutující pokus na nabídku. |
| `public.commerce_tasks` | work kind, aggregate key, dueAt, attempts, worker fence a repair reason; plánuje jen tento protokol, nikoli vlastní odesílání e-mailů. |

Externí finanční fakta patří do jedné evidence `public.commerce_payment_facts` navázané na kanonické payment_info/order, nikoli do falešných bankovních pohybů. Částky v minor units nebo přesném NUMERIC s explicitní měnou, nikdy JS float účetnictví. Zdroj může být provider nebo doložená ruční oprava; původ musí být rozlišený.

## 6. Jediná obsazenost kanonické kapacity

Rozhodnutí návrhu: rozšířit `eshop.spots` o `capacity_reservation_id` (FK na rezervaci). Je to claim skutečné existující jednotky; nová tabulka není druhá skladová zásoba. Zápis má explicitní SQL operace, žádné aplikační triggery. FK je RESTRICT a při non-null pointeru CHECK zakáže současný order_product_ticket nebo browser secret; historické řádky bez pointeru se touto novou podmínkou nemění.

Pro konkrétní řádek platí nejvýše jeden vlastník: `order_product_ticket`, aktivní browser hold, nebo `capacity_reservation_id`. Při převzetí holdu se ve stejné transakci odstraní secret a přiřadí externí rezervace. Při převzetí do objednávky se ve stejné transakci změní externí claim na příslušný order_product_ticket. Neexistuje okamžik, kdy by místo bylo mezi těmito stavy volné.

Nový čistý helper `public.inventory_spot_is_occupied_internal(order_item, hold_secret, hold_until, external_reservation, at_time)` sjednotí význam: ordered OR active browser hold OR external claim. Pointer na externí rezervaci blokuje kapacitu bez ohledu na čas. Správný explicitní release ho odpojí teprve po doložení nepřijetí/revokace. Helper nesmí načítat hodiny skrytě; read projekce používají jediný předaný čas snapshotu. Zápisové admission hodnotí pod zámkem aktuální čas.

Změna patří současně do čtyř skupin:

- **Přidělení:** `select_spot`, `blueprint_hold_admission_internal`, materializace ticketů, `apply_allocations`, administrační vytvoření/výměna, waitlist a batch cesty. Aktivní externí claim se nesmí chovat jako vypršelý secret.
- **Limity:** pool sellable capacity, fyzické jednotky každého PIC, product maximum a form participant_capacity zahrnou rezervované intended-ticket quantities. Nepočítat jeden ticket několikrát kvůli závislostem ve více kontextech. Převzetí vlastního claimu nezapočítá tutéž spotřebu dvakrát.
- **Čtení:** blueprint state, dostupnost produktu/formuláře, katalogy, management/reporting. Veřejnost vidí jen anonymní reserved/unavailable a počty; žádný externalAccountRef, cart code, secret, order ani osobní údaje.
- **Údržba a zásahy:** změna kapacity, smazání pool/resource, seat edit/swap, ruční release, kopírování akce, delete/storno objednávky. Externí claim nelze obejít rolí běžného správce. Kopie nikdy nepřenese claim ani jeho pointer; zmenšení nesmí claim vymazat.

Admin preview snapshot/digest musí zahrnout capacity_reservation_id a reservation revision. Preview po změně claimu není potvrzení aktuálního stavu. Ruční tlačítko „Uvolnit“ má u externího claimu znamenat spuštění bezpečného externího vypořádání, ne UPDATE na volné místo.

Zamykání: převzít existující occasion/blueprint scope owner, potom agregáty checkout/offer ve stabilním pořadí, form/order, product/inventory rodiče a nakonec spots podle ID. Nové cesty se musí řídit skutečným společným pořadím z `lock_blueprint_scope_internal`, `lock_order_capacity_scope_internal` a `lock_ticket_order_products_internal`; nenapsat druhé rozporné pořadí. Pokud operace zahrnuje více akcí, má je zamknout seřazeně před podřízenými řádky, nebo ji profil V1 odmítne. SQL transakce nikdy nedrží zámky během HTTP.

## 7. Stavové automaty - tři nezávislé osy

### Nabídka poskytovateli

`draft -> prepared -> sending -> accepted | rejected | unknown`.

- prepared znamená kapacitu chráněnou v DB a trvale uložený payload, ne aktivní checkout.
- accepted znamená odpověď PUT s uloženým a ověřeným kódem, ne přijetí objednávky nebo platbu.
- unknown znamená, že provider mohl mutaci provést. Automatický další PUT stejné ani nové revize není povolen.
- Pro další nabídku je nutné bezpečně ohraničit dřívější sender a zjistit dopad staré nabídky. TTL lease sám nezastaví zpožděný proces.

### Kapacita rezervace

`held -> transferred` nebo `held -> release_pending -> released`.

K rezervaci se vede resolution `clear | awaiting_provider | conflict`. Vypršení času mění resolution na awaiting_provider, nikdy samo disposition na released. transferred znamená atomické předání kanonické objednávce; nezaplacená objednávka už není krátký browser hold.

### Objednávka a finance

`observed -> admitted -> awaiting_payment -> paid`, případně cancellation/refund/review. Převzetí objednávky má stabilní unikátní klíč a jednou přiřazené domácí order ID. Refundace je samostatný finanční fakt, nikoli automatický návrat do unpaid nebo volného místa. Použitá vstupenka vyžaduje explicitní pravidlo řešení vrácení, ne automatické znovuvydání.

Tyto osy se nesmějí slít do jedné proměnné status. HTTP 200 z PUT není placeno; browserový timer není cancelled; refundace není storno všech položek.

## 8. Interface modulu Commerce Connector

Koordinátor dostává SQL port, provider adaptér, clock a audit sink jako závislosti. Tím lze ověřit stejné interface s fake HTTP i skutečným sandboxem. Helpery state machine nejsou další veřejné funkce pro každého klienta.

| Operace | Vstup | Výsledek / invarianta |
| --- | --- | --- |
| `readCheckout` | serverově ověřená browser session a checkout key | aktuální revision, selection, display status a allowedActions; bez provider secrets. |
| `prepareCheckout` | session, expectedRevision, commandId a selection | prepared/ready/conflict/processing; source cart, currency a mapování ověřuje server. |
| `requestRelease` | session/operator, expectedRevision a commandId | release_pending; nevrací „volno“, dokud není bezpečně rozhodnuto. |
| `recordProviderEvent` | raw body + signature metadata | durable inbox receipt po ověření; neprovádí finanční důvěru podle browseru. |
| `reconcileCheckout` | service-only aggregate ID + worker fence | validovaná pozorování provider stavu, poté SQL transition. Ne HTTP volání v SQL. |

Instalace a mapování jsou admin konfigurace mimo browserový checkout interface. Read detailů objednávky, sjednocení finance a obsluha webhooku patří do stejného modulu, ne do jednotlivých UI handlerů.

Browser request příklad, nikoli již existující endpoint:

`{checkoutId, expectedRevision: 7, commandId, selection: [{mappingId, quantity, seatBindingIds}]}`.

Odpověď: `{checkoutId, revision: 8, status, selection, offerExpiresAt, allowedActions, errorCode?}`. Ověřovací kód, pokud ho vyžaduje nativní checkout, dostane pouze oprávněná session pro právě tuto nabídku; není to Shoptet API token. Označit ho za bearer citlivé pole, nelogovat a nevkládat do URL.

Chyby: 409 REVISION_CONFLICT/CART_CHANGED/CAPACITY_UNAVAILABLE; 403 SCOPE_DENIED; 422 UNSUPPORTED_CART; 429 HOLD_LIMIT; 202 PROCESSING/RECONCILIATION_REQUIRED; 503 PROVIDER_UNAVAILABLE. Neznámý výsledek nesmí být prezentovaný jako jisté zamítnutí. Po konfliktu se vrátí aktuální bezpečná projekce, nikoli interní řádky nebo raw provider error.

## 9. Průběh normálního nákupu

1. Instalace je ověřená a enabled; mapování i supported profile projdou serverovou kontrolou. Samotné zobrazení stránky žádnou kapacitu nezablokuje.
2. Browser předá identifikátor košíku a výběr. Server si načte košík přes token konkrétní instalace a ověří jeho vazbu, SKU, množství, měnu a mapování.
3. SQL pod správným scope lockem porovná revision a command digest, ověří dostupnost a přidělí všechny jednotky najednou. Neúplné přidělení se vrátí celé zpět. Vytvoří immutable offer a pending attempt.
4. Worker si trvale přivlastní external attempt, ukončí SQL transakci, zavolá publishAuthorization a uloží bounded výsledek. Browser teprve po jistém výsledku převezme providerem vyžadované veřejné potvrzení a expiraci.
5. Shoptet přijme platnou nabídku a přiřadí orderCode. Webhook je hint k načtení nebo ověřenému srovnání; unikátní business klíč zabrání druhému importu.
6. Server načte detail a ověří shodu s rezervací. SQL atomicky vytvoří/převezme order a přesune kapacitu do kanonických order_product_ticket bez nového odečtu.
7. Podle doložených finančních faktů se použije existující paid transition a `enqueue_paid_order_tickets`. Šablona bere externí platební zdroj a nevytvoří druhou výzvu k platbě. QR, PDF, skenování i export používají stejné tickets jako přímý prodej.

Shoda při admission se týká identity položek, množství, měny, rezervovaných míst a dohodnutých vázaných částí cart snapshotu. Finální nativní ceny se přebírají z ověřené externí objednávky podle G5, nikoli zpětně z dnešního katalogu Festappu; nedostupné per-item ceny v předběžném CartSnapshotu se nevymýšlejí. Změna slev/částek mimo podporovaný kontrakt je conflict.

Neshoda přijaté objednávky není oprávnění vytvořit „nejbližší“ alternativu. Rezervace se chrání a vznikne viditelný conflict s podklady.

## 10. Dvě záložky, změna košíku a změna výběru

Každý command nese expectedRevision a idempotentní commandId; stejný command se stejným digestem vrátí původní výsledek, změněný obsah pod stejným commandId se odmítne. Dva různé commands se starou revision nemohou oba přepsat stav. Všechny price/selection úpravy se serverově ověřují; lokální cache je pouze návrh.

Během mutujícího provider pokusu checkout nepřijme další změnu. Pokud se má změnit už zveřejněná nabídka, nejprve musí být doložen bezpečný provider contract pro její zneplatnění nebo nahrazení. Do té doby první profil **nedovolí in-place výměnu zveřejněných míst**. Ukáže stávající výběr a čekání na bezpečné ukončení; nová session nezíská právo stará místa uvolnit.

Toto omezení zabraňuje našemu opožděnému senderu přepsat novou nabídku. Neřeší samo změnu množství provedenou přímo v Shoptetu: pro tu stále platí brána G2/G3. Pokud Shoptet dovolí použít starý kód pro jiné položky, návrh této integrace nelze označit za bezpečně dokončený.

Aktualizace obrazovek může používat krátké stavové čtení po návratu/focus a během processing; cross-tab signal nebo realtime je nepovinné UX. Povinností je nové autoritativní čtení před rozhodnutím, obnova při focus/visibility a ignorování pozdních výsledků staré revision. Návrat z jiného zařízení je jiný košík, dokud není jeho převzetí výslovně a bezpečně implementované.

## 11. Expirace, nejisté HTTP a reconciliation

Rozhodující příklad: nabídka expiruje ve 12:00:00, objednávka je přijata v 11:59:59 a webhook přijde ve 12:00:03. Ve 12:00:00 musí external claim stále chránit původní jednotky. Pravidelný reconciliation worker zjistí přijetí a převede je do objednávky.

| Pozorování | Akce |
| --- | --- |
| PUT timeout / přerušená odpověď | attempt unknown; žádný slepý PUT retry; chránit claim, zabránit dalšímu senderu. |
| GET timeout, 429 nebo 5xx | bounded retry s Retry-After/backoff pro čtení; nic neuvolnit. |
| Expirace nabídky | zastavit dostupnost staré browserové nabídky, označit awaiting_provider a přečíst stav. |
| completed + odpovídající detail | idempotentně admitOrder a transfer claimu. |
| open/cancelled/404 bez doložené finality | stav je evidence, ne release permission; dál chránit kapacitu a předat repair při vyčerpání rozpočtu čtení. |
| Doložené konečné nepřijetí nebo nevratná revokace této nabídky | explicitní SQL release pod očekávanou revizí a evidence digestem. |
| Starý proces může ještě provést PUT | nejprve skutečně ukončit/ohraničit původního sendera; lease expiry nestačí. |

Konkrétní defaulty pro polling/backoff jsou provozní konfigurace ověřená proti sandboxu a limitům; nejsou nově slíbené SLA. Po rozpočtu pokusů vznikne repair job; kapacita zůstane blokovaná. Automatický repair timeout nikdy nesmí znamenat free. Omezit počet aktivních/nejistých rezervací na session, instalaci a organizaci; při překročení bezpečnostního rozpočtu pozastavit nové nabídky a upozornit obsluhu.

## 12. Finance, změny a doručení

Privilegované převzetí používá zmrazené skutečné ceny Shoptet položek, slevy, DPH a měnu; běžný veřejný finalizer nadále počítá jen svůj důvěryhodný katalog a nepřijímá klientské paid nebo price override. Nutná změna se provede vytažením sdílené materializace, ne přidáním anonymního flagu do stávajícího endpointu.

Externí payment source je explicitní: payment_method=external_commerce a vazba na commerce installation/order link; konkrétní provider je metadata této vazby, ne nový účetní algoritmus. `payment_financial_totals_internal` a refresh projekce zahrnou právě jednou validované externí facts; nevytvářejí bank transakci ani `paid_externally` jako náhražku. Odpojí se místní bank matching, Stripe pay link, platební reminder a generická reaktivace expired pro tento zdroj. Read reporty a ruční úpravy zdroj respektují.

PaymentTransaction OK, paid flag, ruční potvrzení a refundace se mapují až podle G5. PENDING/NEW/FAILED/UNKNOWN nestačí k vydání; null paid také ne. Aggregate snapshot není nový pohyb při každém webhooku. Částečné vrácení se váže ke konkrétním položkám; záporný pohyb neznamená automatické uvolnění sedadel. Cena po již potvrzeném prodeji se bez revizovaného opravného kontraktu nepřepisuje.

Domácí order payment deadline nesmí spustit obyčejné uvolnění externího prodeje, dokud Shoptet může přijmout pozdní platbu. Pro první profil není automatická místní expirace nezaplacené externí objednávky povolená. Její zrušení začíná externím doloženým procesem; teprve potom se mění platnost ticketu a kapacita. Při platbě po zrušení vznikne conflict, ne tichá reaktivace nebo přidělení jiného místa.

Dodržet jeden effect intent a existující email/payment version guard. Opakovaná notifikace nevydá druhé QR ani druhý přijatý delivery intent. Samotný provider transport e-mailu nemusí zaručit exactly-once; tento návrh to nově neslibuje.

## 13. Oprávnění, instalace a provozní přístupy

- Typed operations vlastní user_permissions/commerce_operations.sql: can_manage_commerce_occasion deleguje na can_author_forms pro mapování a propojení konkrétní akce; can_read_commerce_status na can_read_form_catalog bez PII; order conflict detail na can_read_orders; request reconcile/release na can_write_orders. Změna credential/unit vazby nebo pozastavení celé instalace vyžaduje manage právo ke všem jejím namapovaným akcím; správce jedné akce smí vypnout jen její mapping. Nová instalace vyžaduje ověřené merchant vlastnictví a oprávněnou počáteční akci, od níž se unit odvodí. Veškeré obchodní scope se váže uloženými řádky a znovu kontroluje i při replay. Globální service key sám validaci scope nenahrazuje.
- Admin linking ověří vlastnictví Shoptet e-shopu a oprávnění k unit/occasion; uloží vazbu. Browser si nesmí vybrat cizí externalAccountRef a tenant. Callback URL/OAuth host se bere z ověřené instalace, ne libovolné browser adresy; zakázat redirecty na jiné hosty.
- Browser session začíná ověřitelným košíkovým kódem a instalací, kterou server potvrdí přes provider. Košíkový kód je citlivá capability, ne veřejný vyhledávací klíč. Krátká opaque session capability se předává v těle/headeru, ne URL; pro iframe nevyžadovat funkční third-party cookies. Přesná origin allowlist + rate limits, žádný wildcard s credentials. Origin sám neprokazuje vlastnictví košíku.
- Provider secrets nikdy nejsou v UI, preview, telemetry nebo Git. Webhook podpis ověřit nad raw tělem správným instalačním klíčem, s omezením velikosti. Durable inbox uložit před HTTP ack; zpracování asynchronní. Neověřený webhook nečte osobní data ani nemění finance.
- Pozastavení blokuje nové nabídky; přijaté objednávky a nejisté claimy se chrání. Po uninstall nepředpokládat funkční API. Vydané vstupenky a skenování pokračují; změny bez oprávněného přístupu čekají na reconnect nebo doložené ruční řešení.
- Reinstall ověří stejný e-shop, novou autorizaci a oprávněné staré vazby. Credential generation odděluje práva; nesmí změnit obchodní deduplikaci. Raw event se starým podpisovým klíčem nemá automaticky právo přepsat novou instalaci.

V prvním Shoptet adaptéru musí instalace udržet atypical shipping konfiguraci; jeho health check ji kontroluje a vrací normalizovaný contract health. Jiné adaptéry ověřují vlastní konfiguraci, jádro žádný atypicalShipping nezná. Zjištěná změna pozastaví nové nabídky. Monitoring změny není ochrana časového okna, proto backendový G2 test zůstává povinný.

## 14. UX a obsluha incidentů

Kupující vidí „Vyberte vstupenky“, „Rezervace platí do…“, „Ověřujeme objednávku“ nebo konkrétní konflikt s obnovením výběru. Text „Uvolněno“ se zobrazí až po explicitním release. Po serverové změně se zachovají nesouvisející kontaktní údaje. Žádný úspěch jen podle návratu z platební stránky.

Pořadatel vidí stav instalace, poslední úspěšné srovnání, počet held/awaiting_provider, order konflikty, aktivní externí alokace a důvod pozastavení. Akce „Zrušit rezervaci“ spouští requestRelease, „Ověřit stav“ plánuje read-only reconciliation. Tlačítko „Vynutit uvolnění bez důkazu“ není běžná funkce. Opravné rozhodnutí má roli, důkaz a auditní záznam; nemění svévolně finanční fakta.

Klíčové metriky: stáří nejistého attemptu, stáří nejstaršího blokovaného claimu, selhání podpisu, konflikty snapshotu, počet nezpracovaných inbox jobs, úhrada bez přijaté alokace, stav provider API a počet opakovaných commandů. Logs obsahují interní aggregate/attempt IDs a bounded codes, ne košíkový kód nebo kontakt zákazníka.

## 15. Konfigurační a registrační kontrakt

Jeden Edge vstup rozlišuje route třídy: instalační callback, provider event, buyer session/checkout a authenticated admin. Pro každou se explicitně vyhodnotí její autentizace; možnost veřejného OAuth callbacku/webhooku není povolení anonymních admin nebo ingest operací. Pokud funkce musí mít verify_jwt=false, route-level validace JWT/signature/capability se testuje pro každou route i neznámé provider ID. Callback nelinkuje tenant z query parametru.

Registry provider adaptérů je statický composition root. connector.ts ani inventory SQL neimportuje Shoptet adapter a neobsahuje přepínač provider=shoptet. Provider capability profile je versioned evidence-backed konfigurace, ne sada ifů ve formuláři. Žádný konektor nepřijme automaticky wider scopes při upgrade.

Integration package manifest uvádí provider/app identity, supported profile, deklarovaná oprávnění a browser bundle. Oprávnění a provozní secrets se přidělují odděleně. Částky, inventory funkce nebo seznam eventů se neduplikují do manifestu jako druhý zdroj business pravidel.

## 16. Pořadí ověření před větší implementací

Nejdřív minimální provider probe ověří v oprávněném sandboxu G1-G4 nad disposable testovací evidencí. Nepotřebuje předem přepsat všechny domácí SQL cesty. Takový experiment ověřuje Shoptet kontrakt, nikoli hotovou integraci nebo bezpečnost produkční kapacity. Teprve po průchodu má smysl rozšiřovat společné inventory a kanonický import.

Při zakázaných sandboxových mutacích nebo chybějících přístupech se smí připravit jen lokální harness a design; G1-G4 zůstávají neověřené. Nejde o důvod automaticky kontaktovat podporu nebo implementovat alternativní obchodní cestu.

## 17. Co je připravené a co ještě není

Připravené: cílová architektura, stavové automaty, storage návrh, interface, error model, vlastnictví kapacity, bezpečný recovery model, testovací matice a etapy. Existující Festapp vlastní SQL rezervace, objednávky, vstupenky a frontu; externí claims a Shoptet finanční source se musí teprve doplnit.

Neověřené: G1-G5 a reálné chování API při S1-S10. Není hotová migrace, worker, callback, widget ani sandboxový průchod. Nelze to prezentovat jako spuštěnou integraci. Největší zbytkové riziko je neprokázané serverové navázání nabídky na obsah/finalitu; bezpečné držení kapacity to samo nepromění ve správný nákup.

## 18. Produktové důsledky první verze

- Zveřejněný výběr míst se do ověření bezpečné provider revokace neupravuje in-place. Otevření druhé záložky ukáže stejný serverový výběr nebo konflikt. Toto omezení bude v UI viditelné, nikoli tiché.
- Při nejasném externím výsledku mohou být konkrétní místa dočasně nedostupná. Operátor má přehled a repair postup; nevznikne druhý prodej za cenu zdánlivě vyšší dostupnosti.
- Nepodporovaná změna zaplacené objednávky/refundace se musí detekovat a předat k doloženému řešení. Nesmí být ignorována jen proto, že automatický scénář není v pilotu. Kanonické zneplatnění příslušných ticketů a scan projections musí být součástí implementačního testu před aktivací; kapacita se nevrátí automaticky.
- Schválení návrhu architektury není důkaz funkčního Shoptet backendu. Vývoj, sandboxové ověření a produkční aktivace mají odděleně evidovaný skutečný výsledek.
