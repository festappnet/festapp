# Jednotná politika platebních metod, finančních operací a komunikace

Datum: 2026-11-12  
Stav: Připraveno pro implementaci, bez změny provozu  
Ověření při implementaci: standard (platby, oprávnění, databázové kontrakty)  
Podklad: lokální pracovní strom nad `742d614b7`, větev `docs/festapp-tickets-readme-20261107`; obsahuje rozsáhlé nesouvisející rozpracované změny. Zjištění níže popisují pracovní strom, nikoli ověřený stav produkce.

## Výsledek a hranice

Festapp Tickets Global má bankovní službu vypnutou pro celý tenant. Bankovní převod, výběr přijímacího účtu, konfigurace referencí a související nové platební instrukce se neobjeví v jeho běžných pracovních postupech. Stripe je preferovaný konektor. Skutečný prodej vyžaduje připravené připojení a výslovnou provozní aktivaci.

Stejná koncepce platí pro banku, hotovost a každý instalovaný externí konektor. Tenant rozhoduje, co povoluje, unit může povolení dále omezit, formulář vybírá metody z tohoto průniku. Není to sada nezávislých příznaků pro jednotlivé obrazovky. Oprávnění uživatele zůstávají samostatnou podmínkou.

Součástí práce jsou SQL, běžné i administrátorské objednávky, finanční ledger a bankovní výpisy, párování/korekce/refundy a jejich QR, MCP, Flutter, veřejný web, průvodce založením/kopírováním, e-maily, náhledy, migrace a cílené regresní testy. Nezahrnuje integraci další brány, změnu obchodního modelu, automatickou změnu metody existujících objednávek, produkční migraci, aktivaci skutečných plateb ani nasazení. Vstupenkové, přihlašovací a peněženkové QR kódy zůstávají funkční.

## Doložený současný stav

| Fakt | Konkrétní zdroj | Důsledek |
|---|---|---|
| Existuje SQL registr instalovaných metod, bank/cash a externí adaptéry. | `database/functions/payment_providers/schema.sql`, `registry.sql`, `builtin.sql`; `docs/architecture/payment-providers.md` | Rozšířit tento systém, nezavádět druhý registr konektorů. |
| Konfigurace formuláře již obsahuje `bankEnabled`, `cashEnabled`, `providerConnections`. | `payment_providers/configuration.sql`: `merge_form_payments_internal`; `eshop_forms/form_settings.sql` | Konfigurace formuláře není tenantové povolení. Dnes se chybějící banka a JSON null normalizují na true. |
| Bankovní dostupnost vychází z formuláře a propojených účtů. | `payment_providers/builtin.sql`: `bank_payment_provider_internal('form_availability', ...)` | Chybí jednotná politika organizace a unit pro všechny metody. |
| Registry volá provider-specific `unit_feature` a `unit_fields`; Stripe má vlastní unit feature tabulku. | `eshop_stripe/feature_settings.sql`, `eshop_stripe/provider.sql`; `eshop_barion/provider.sql` | Oddělit jednotné povolení od technické/provozní připravenosti konektoru. Barion vrací unit feature false. |
| Global provisioning už deklaruje Stripe jako výchozí metodu. | `automation/release/tenants/provision_festappticketsglobal.sql`: `DEFAULT_FORM_PAYMENT_METHOD=stripe` | Část cíle již existuje; stejný skript zakládá runtime policy s `new_payments_enabled=false`. To není důkaz živého stavu. |
| Nový online formulář začíná s `bankEnabled=false`, bez vymyšleného příjemce. | `eshop_forms/form_creation_domain.sql`: `insert_form_for_occasion_internal_v1` | Zachovat zavřený koncept do připojení účtu, rozšířit na všechny vstupy včetně kopií. |
| Wizard překládá tenant default a legacy `paymentMethod`. | `occasion_setup/drafts.sql`, `finalize.sql`; `configuration.sql`: `normalize_setup_payments_internal` | Nelze řešit jen nový formulář; reset a staré drafty mohou vrátit bankovní výchozí hodnoty. |
| Web i Dart při chybějící dostupnosti předpokládají banku. | `web_client/src/components/forms/form_payment_options.js`; `packages/festapp_core/lib/src/forms/form_payment_options.dart` | Chybějící projekce nesmí povolit metodu zakázanou politikou. |
| SQL finalizace při chybějící metodě volí bank/cash; instrukce vydává samostatný vlastník. | `eshop/finalize_ticket_order.sql`: `finalize_ticket_order_internal_v1`; `eshop_orders/ensure_order_payment_instructions.sql` | Přímý požadavek i starý klient musí projít stejným serverovým zákazem. |
| Potvrzení podporuje hosted konektory a bankovní QR je na několika místech podmíněné metodou. | `send-email/getTicketOrderConfirmationTemplate.ts`; `_shared/payments/email.ts`; update/paid template handlery | Již fungující části sjednotit; nepsat nový checkout ani novou frontu e-mailů. |
| Reminder renderer dereferencuje bankovní účet a vytváří QR bez obecného rozlišení metody. Plánování nemá filtr typu metody. | `send-email/getTicketOrderReminderTemplate.ts`; `emails/queue_payment_reminders.sql` | Nutná změna plánování i přípravy a předodesílací kontroly; skrytí UI nestačí. |
| Některé sdílené texty používají bankovní větev pro ostatní metody. | `_shared/orderEmailPresentation.ts`: confirmation/update/reminder; `_shared/confirmationContent.ts` | Všechny typy zpráv musí používat stejný kontrakt prezentace plateb. |
| Proměnné e-mailů mají jeden generovaný kontrakt a náhledy vlastní generátor. | `packages/festapp_contracts/email-variables.json`; `automation/generate_email_variables.py`, `generate_email_preview_examples.ts` | Nové proměnné a jejich dostupnost přidat do zdroje, ne ručně do generovaných TS/Dart souborů. |
| Bankovní účet může obsluhovat více unit, bankovní oprávnění vyžadují existující dvojí roli. | `lib/components/bank_accounts/README.md`; `user_permissions/bank_operations.sql`, `context_capabilities.sql` | Zákaz jednoho scope nesmí zastavit synchronizaci jiného ani udělit správu účtu tenant adminovi. |

Doplněná evidence finančního životního cyklu:

| Fakt | Vlastník a konkrétní mezera | Architektonický důsledek |
|---|---|---|
| Společný engine už vlastní `record_payment`, `prepare_refund`, `cancel_pending`, `correct_record`, preview a receipty. | `payment_providers/operations.sql`, `operation_contexts.sql`, `operations_schema.sql`; `user_permissions/payment_operations.sql` | Rozšířit jeho rozhodnutí, nevytvářet druhý engine/refund ledger. Prepared RBAC zůstává privátní; command znovu autorizuje. |
| Online objednávce context vybírá pouze její uložený konektor; offline objednávce nabízí builtin metody podle capability. | `payment_method_contexts_internal`; `builtin.sql: bank_refund_readiness_internal` | Zachovat izolaci gateway; bankovní refund vyžaduje původní účet/namespace/VS či RF a BankSync, samotný bankEnabled nestačí. |
| Ledger odděluje skutečné peníze od rezervace refundu. | `eshop_transactions/payment_totals.sql`, `payment_providers/financial_facts.sql`, `registry.sql: provider_payment_movements_internal` | Přijaté/vrácené/net/held/pending nezávisí na aktuálním povolení prodeje. Chybějící provider facts nejsou nula. |
| Detail objednávky vrací všechny osobní admin bank účty bez omezení na metodu objednávky. | `eshop_transactions/get_transactions_for_order.sql: actions.historyAccounts`, `canConfigureBank`, `bankState` | Odstranit propojení order finance -> nesouvisející bank statement. Gateway finance nemají odkaz na bankovní správu. |
| Obecný detail čte `eshop.transactions`, gateway movements mají samostatný registry reader. | `get_transactions_for_order.sql`; `registry.sql: provider_payment_movements_internal`; `transactions_dialog.dart` | Sjednotit čtecí finanční projekci, ne kopírovat gateway fakta do bankovní tabulky a ne skrýt finance celé. |
| Refund UI při cash přidává nepoužitelnou bankovní položku pro discoverability, i když ji server neposlal; není to důkaz vykonatelného bypassu. Znovuotevření requestu používá uložené instructions. | `payment_operation_dialog.dart: _refundMethods`, `_request`; `operation_contexts.sql: requests.canReopen/instructions` | Záměrná cross-method podpora musí být explicitní serverová capability, nikoli odhad widgetu. Historická instructions nejsou trvale platné oprávnění zobrazit QR. |
| Edge dekoruje libovolné neprázdné instructions do SPD/EPC bez kontroly uloženého zdroje. | `_shared/payments/operationHandler.ts: decoratePaymentOperation`, `presentRefundInstructions` | Výstup potřebuje purpose a ověřené serverové eligibility, nestačí přítomnost IBAN. |
| Pairing již brání přiřazení bank pohybu online objednávce a chrání refund settlements/rezervace. | `eshop_transactions/apply_transaction_pairing.sql`; add/remove/delete wrappers | Zachovat tyto guardy a audit; doplnit product policy do uživatelských vstupů, ne zastavit ověřený ingest. |
| Provider refund používá durable intent, lease a read recovery. | `refund_dispatch.sql`, `_shared/payments/refunds.ts`, `connectors/stripeRefund.ts` | Sales disable nesmí zabránit vypořádání staré gateway platby ani opakovat nejistý refund zápis. |

Reprezentativní finanční cesta: order grid/detail -> `get_transactions_for_order` / bulk `payment_method_contexts_internal` -> `get_payment_operation_context` / preview -> `command_payment_operation` -> registry handler -> cash commit, bank instruction reservation nebo provider durable intent -> BankSync debit / verified provider movement -> existující totals/effects -> ledger a delivery. `refund_requests` jsou záměry, nikoli potvrzené finanční pohyby. Žádný UI krok, browser return ani úspěšný HTTP dispatch nesmí sám potvrdit vrácení peněz.

Reprezentativní cesta: tenant/unit -> založení či kopie události/formuláře -> uložená konfigurace -> dostupnost pro konkrétní měnu/povrch -> SQL objednávka -> instrukce nebo checkout attempt -> ověřená finanční fakta -> fronta -> renderer -> připravený snapshot -> předodesílací gate. Každá uživatelská mutace musí ověřit podmínky svého účelu podle uložené hierarchie, i když klient má starý snapshot; ingest skutečných finančních faktů není nová nabídka metody.

## Cílová architektura a rozhodnutí

### 1. Jedna doménová politika, oddělená od RBAC a připravenosti

Rozšířit existující modul `payment_providers/` o soukromé typované tabulky tenantové a unitové politiky. Navržené názvy: `eshop.organization_payment_method_policies` a `eshop.unit_payment_method_policies`. Obě odkazují na již existující `eshop.payment_providers.provider_key`, nikoli na druhý katalog. Tenantový řádek obsahuje `enabled`; unitový override je `inherit` nebo `disabled`/`enabled`, přičemž enabled nikdy nepřebije zákaz tenantu. Preferovaná metoda patří do jednoho nastavení platebního scope, ne do konkurenčních booleanů na každé metodě. Změny mají audit a revizi.

Jeden privátní SQL resolver, pracovně `resolve_payment_method_policy_internal(organization, unit)`, vrací pro každou instalovanou metodu povolení, původ rozhodnutí, preferenci a stabilní důvod zákazu. Nevolá vzdáleného poskytovatele. Scope musí patřit do stejné uložené hierarchie; ID zaslané klientem ji neurčuje.

Efektivní možnost přijmout novou platbu je průnik:

`installed AND organizationEnabled AND unitEnabled AND formSelected AND connectorReady AND currencySupported AND surfaceSupported AND runtimeSalesEnabled`.

RBAC se přidává podle operace: oprávnění spravovat politiku, připojit účet, upravit formulář a provést finanční operaci jsou odlišná. Veřejný nákup nevyžaduje správcovské oprávnění. Nikdy se nepoužije obecné `isAdmin` místo existujících typed operation predicates.

Rozšířit dnešní `form_payment_availability_internal`, setup/editor/unit projekce a kontextové capabilities ze stejného resolveru. Administrátor dostává `supported`, `policyEnabled`, `configured`, `ready`, `available`, `reason`, `inheritedFrom`, `canConfigure`. Veřejná projekce dostává pouze potřebnou dostupnost a bezpečné důvody, bez cizích účtů, tokenů či interních údajů. Rozlišovat `organization_disabled`, `unit_disabled`, `not_configured`, `connector_unavailable`, nepodporovanou měnu/povrch a provozně zavřené prodeje.

Bankovní metoda v dnešním modelu znamená přímý převod na účet s vlastními instrukcemi. Bankovní varianta nabízená uvnitř Stripe checkoutu patří konektoru Stripe; nezakazovat ji porovnáním zobrazovaného názvu. Výplatní účet pořadatele u externí brány rovněž není přímá bankovní platební metoda Festapp.

Podpora se vyhodnocuje pro konkrétní operaci, nikoli jedním obecným booleanem. Konektor může přijímat platby a pozorovat externí refundy, aniž umí refund vytvořit; může podporovat jen plnou refundaci. Použít existující registry handlers a operation contract, doplnit pouze chybějící deklarace. Rozlišit refund write, partial refund a refund observation a skutečnou dostupnost pro uložený účet, prostředí, měnu, částku a stav. Neznámá deklarace neposkytuje schopnost implicitně. Technickou nepodporu (`unsupported_operation`) odlišit od dočasné nedostupnosti, chybějícího oprávnění a vyčerpané refundovatelné částky. Tenantová policy nikdy nedoinstaluje schopnost konektoru.

Pokud brána refund write nepodporuje, UI nenabízí spustitelnou refund akci, preview/command ji odmítnou bez vytvoření intentu, rezervace nebo remote write a žádné bank/cash/QR náhradní workflow se nevytvoří. Finanční panel může nezávisle zobrazit vysvětlení nepodpory. Je-li refund observation podporováno, skutečný externí refund se nadále zobrazí a započítá. Odkaz do portálu brány lze nabídnout pouze tehdy, pokud jej její existující descriptor explicitně a bezpečně podporuje; není to potvrzení provedené refundace. Full-only konektor odmítne partial refund i přes přímé RPC a částku potichu nezmění. Tyto invarianty implementovat ve vlnách 2 a 3 přes společný action kontrakt.

### 2. Globální a regionální výchozí stav

- Global: `bank.enabled=false`, `stripe.enabled=true`, preferovaná metoda `stripe`. Hotovost nepovolit nově implicitně. Ostatní konektory jen podle výslovné tenantové politiky a skutečných podporovaných schopností.
- Nové unit dědí tenant; unit může jednotlivé metody dále vypnout. Pokud vypne preferovanou metodu, musí vybrat jinou povolenou nebo ponechat placený prodej zavřený. Nikdy automatický fallback na banku.
- Dosavadní tenanty zachovají při migraci svou doloženou konfiguraci a dostupnost. Neukládat globální změnu výchozí hodnoty banky pro všechny.
- Nově instalovaný konektor je bez tenantového povolení zakázaný. Chybějící řádek po migraci znamená zákaz, ne implicitní povolení. Rozlišení historických defaultů provést jednorázovým backfillem.
- Povolený Stripe znamená dostupný onboarding a možnost konfigurace. Chybějící připojení, runtime zákaz a Barion sandbox-only zůstávají důvodem nepřijímat platby.

### 3. Operace, oprávnění, ledger a bezpečné vypnutí

**Terminologie:** scoped `enabled` je product policy; `runtimeSalesEnabled` je samostatná provozní připravenost přijímat nové platby. „Sales disable“ znamená zákaz nových collection akcí; „bank service disable“ navíc zavírá bank authoring, statement nástroje a použitelné bankovní instrukce v daném scope. Ani jeden pojem neznamená smazání peněz nebo odpojení fyzického účtu.

**Rozhodnutí:** `enabled` je povolení používat metodu v daném produktu/scope, nikoli existence peněz. Dostupnost nového prodeje se nesmí používat jako univerzální guard historie, refundu, storna, korekce ani recovery. Pro banku zákaz navíc zavírá její bankovní authoring a nové či znovu zobrazené převodní instrukce v tomto scope. Gateway servis staré platby není použití přímé bankovní služby.

Rozšířit společné SQL rozhodování v `operation_contexts.sql`/`operations.sql` o purpose-specific eligibility, pracovně privátní `payment_action_eligibility_internal`. Používá stejný scoped policy resolver, uloženou objednávku/request/transaction a registry. Kontrakt má `action`, `method`, `purpose`, `visible`, `allowed`, stabilní `reason` a příslušnou revizi; raw RBAC, connector support a product policy neslévat do jednoho uloženého booleanu. UI může ukázat nepřipravenou povolenou metodu s důvodem, ale skryje bankovní nabídky u zakázané banky a všechny bankovní akce u gateway. Server nedůvěřuje zaslanému `allowed`, ID scope ani instructions. Zachovat dnešní `record/refund` projekce jako odvozený přechodný kontrakt, nikoli druhého vlastníka.

Rozhodnutí pro každou akci je průnik relevantní **product policy + connector support/readiness + typed RBAC + uloženého zdroje a stavu řádku**. Konkrétní relevance:

| Účel | Product policy | Další podmínky |
|---|---|---|
| Nová platba/checkout, nová či obnovená výzva k úhradě | Tenant + unit + form selection | Sales readiness, měna/povrch, skutečný zůstatek, platná splatnost a lifecycle; role pouze u admin authoringu. |
| Nastavení/onboarding, výběr účtu, bank statement v unit | Tenant + unit služby | Vlastní typed permission a uložená vazba účtu; nevyžaduje formSelected ani ready připojení, které právě zakládáme. |
| Historie objednávky, received/refunded/net/pending, spor | Nevyžaduje enabled ani formSelected | `can_read_orders` a řádková vazba. Privátní credentials, celé cizí výpisy a actionable instrukce nejsou historie. |
| Nový refund původním externím konektorem | Servis existující platby je povolen i po sales disable | Původní verified source/account/mode/currency, `refund_write_enabled`, skutečná refund readiness, `can_prepare_order_provider_refund`, dostupná částka po holds/reservations a stav. Žádná bank/cash náhrada. |
| Nový bank refund / zobrazení použitelných bank refund instrukcí | Bank služba tenant + unit povolena, formSelected se nevyžaduje | `can_prepare_order_bank_refund`, původní reference/namespace/účet a evidence; request pending bez potvrzeného settlementu, nezdvojená rezervace. |
| Nový cash receipt/refund | Cash tenant + unit povolen | `can_record_order_cash`, builtin support, částka/stav; receipt je nové přijetí, refund je servicing a nezávisí na aktuálním formSelected. |
| Cancel bank pending bez provedeného převodu; oprava skutečného cash záznamu | Povoleno i po disable jako omezená náprava existujícího řádku | Existing typed RBAC, request/transaction source, důvod a audit; cancel vyžaduje explicitní `transferNotSubmitted`, correction nesmí maskovat nové přijetí nebo výplatu. |
| Ověřený ingest, settlement, dispute/refund observation a recovery | Nevyžaduje sales ani form policy | Service authentication, immutable binding, fencing/lease, původní engine a současné admission guards. |

Správu tenantové politiky autorizovat `can_manage_organization_settings`; unit omezení canonical unit-manager predikátem. Unit manager nepřebije tenant zákaz. Policy command má revizi, audit, stabilní UUID a aktuální autorizaci před replay.

**Vypnutí revidované oproti původnímu plánu:** neblokovat změnu jen proto, že existuje nezaplacená objednávka, budoucí refund, spor či finanční dluh. Takové pravidlo by mohlo znemožnit zavření prodeje právě při problému a blokovalo by gateway servicing. Preview rozliší otevřené collection actions, issued odkazy/reference, pending bank instructions, undispatched/dispatched/unknown provider intents a závazky; command vyžaduje potvrzení konkrétní revize preview. Zákaz zastaví nové collection/authoring/instruction akce a fence neodeslaných výzev. Neprovádí automatické storno, změnu metody, odpuštění dluhu ani deklaraci neplatnosti bankovního příkazu. Již vydané bank instrukce či hosted URL nelze vzít zpět; late payment zůstává finanční fakt a neobnoví uvolněné admission.

Existující gateway refund intent a nový oprávněný refund staré gateway platby zůstávají v témže enginu i po zákazu nových prodejů. Connector write kill-switch/readiness je samostatný: při jeho zákazu žádné nové remote writes, nejisté dřívější writes pouze read recovery podle stávajícího protokolu. Vypnutí bank služby skryje použitelný refund QR i u uloženého pending requestu; rezervaci ale neuvolní. Operátor vidí pending částku/status a může pravdivě potvrdit neodeslání nebo sledovat settlement. K novému bank refundu či opětovnému vydání instrukcí je potřeba explicitně znovu povolit bank službu; nevytvářet implicitní recovery výjimku ani nové univerzální super-oprávnění. Potřeba nouzové bank výplaty při trvajícím zákazu je samostatné produktové rozhodnutí, nikoli skrytý RPC bypass. Finanční závazek zůstává viditelný.

BankSync pokračuje pro skutečné staré pohyby a existující reference. Uživatelské hledání/párování/odpárování bankovních pohybů je bank služba a při disable se odmítá; automatický matcher ověřeného pohybu je příjem faktu a pokračuje. Záznamy vyžadující ruční opravu zůstávají viditelné jako nevyřešené, bez automatické heuristiky nebo rozšíření práv.

Souběh: policy změna a vznik nové collection/instruction akce musí mít společný revizní fence/zámek; rozhodnutí znovu číst po jeho získání. Nepřidávat policy lock za pořadí transaction -> capacity/order -> payment, pokud jiný caller bere zámky opačně. Implementace nejprve sepíše a otestuje konkrétní pořadí nad `apply_transaction_pairing`, `command_payment_operation` a finalizerem. Policy preview zámky pro finanční ledger nepotřebuje držet přes síť. Remote dispatch má durable intent/lease; po hranici disable nesmí vzniknout nový collection dispatch, již nejistý pokus se pouze reconciliuje. Servicing refund není collection dispatch. Replay vrátí stejný finanční výsledek bez opakování side effectu, ale znovu autorizuje a odfiltruje dnes zakázané instructions/QR; uložený receipt není permanentní pay capability.

### 3a. Matice metod a finančních operací

| Uložený zdroj objednávky | Viditelné finance | Záznam přijetí a párování | Refund a oprava | Bankovní QR |
|---|---|---|---|---|
| Bank, služba povolena | Bank/cash pohyby skutečně přiřazené objednávce, refund requests a součty | Bank ingest/matcher; ruční pairing jen přes bank guardy; cash receipt jen skutečná serverová capability | Bank podle původní identity; cash refund jako podporovaný builtin přes existující ledger/rezervace; cash correction jen cash řádku | Collection jen dluh a validní instrukce; refund jen pending oprávněný bank request. CZK SPD, EUR EPC; USD bez QR. |
| Bank, služba zakázána | Stejná finanční historie a aktuální late facts; stav nevyřešených závazků | Žádné bank authoring/pairing; ověřený ingest pokračuje. Cash je samostatná metoda, jen pokud její policy a builtin capability dovolují skutečnou hotovost | Žádný nový bank refund ani reopen instrukcí; bezpečný cancel a přesná cash correction povoleny; cash refund jen skutečně povolený builtin | Žádné nové ani znovu nabízené použitelné bank QR. Historický audit metadata bez runnable payloadu. |
| Cash | Skutečné cash pohyby, korekce a refund history | Cash receipt dle cash policy; žádné bankovní párování | Cash refund/correction dle účelu; bank refund pouze pokud server doloží existující canonical original bank binding, jinak nedostupný | Cash sama žádný QR nemá. Nevytvářet účet/VS jen kvůli refundu. |
| Stripe / jiný schopný gateway | Provider payment/refund/dispute facts, holds a pending request; zachovat finance při disable | Žádný ruční cash/bank receipt, pairing, unpair nebo mazání provider facts | Refund pouze původním connector bindingem s write readiness; disable prodeje jej neblokuje. Korekce pouze verified connector observation | Nikdy bank collection/refund QR, ani při bank policy enabled a administrátorovi všech účtů. |
| Barion v dnešní sandbox implementaci | Verified payment/refund facts a holds | Totéž jako gateway | Aplikační refund write nepodporován; externě pozorovaný refund zůstává viditelný. Bez bank fallbacku | Nikdy bank QR. |
| Neznámá/chybějící connector implementace | Uložená auditní historie; neúplnost označit, nevydávat nulu za skutečnost | Žádné nové operace | Žádné domyšlené schopnosti ani změna metody | Žádné. |

Cross-method offline operace nejsou automaticky chyba: engine už dovoluje cash zaplacení/refund bank objednávky a zachovává původ jednotlivých pohybů. Zachovat tento prokazatelný kontrakt. Bank refund cash objednávky bez původní canonical bank identity podporovaný není; syntetická UI položka nesmí vytvářet zdání funkčnosti ani vynutit nový VS. Nevytvářet v tomto úkolu univerzální směrování výplat mezi metodami. Gateway zůstává oddělená i při kontaminovaných historických datech: nesoulad zobrazit jako auditní problém, nedovolit generickou cash correction obejít gateway source guard (včetně `correct_record` větví před běžným capability výběrem).

### 3b. Matice pohledů a sdílených účtů

| Pohled | Autorita | Bank disabled / gateway objednávka |
|---|---|---|
| Order finance / transakce objednávky | `can_read_orders`, uložené vazby; registry movements a společné totals | Zůstává viditelný. Gateway ukazuje svou platbu/refundy/spory; žádné bank setup tipy, výpisy nebo pairing. |
| Unit bank accounts, account picker, bank setup | Efektivní bank product policy + příslušný existing typed predicate podle read/list/link/manage operace; dvojí role jen tam, kde ji již vyžaduje canonical autorita | Skryté a přímé authoring RPC odmítnuté v disabled unit. Pouhé tenant admin právo nedostačuje. |
| Celý bank statement | Explicitní samostatný account reader, `can_read_bank_transactions` + oprávněný enabled linked unit context | Není součástí order finance. Disabled unit jej neotevře. U sdíleného účtu může oprávněný uživatel přejít do jiné skutečně propojené enabled unit, jejíž samostatná account autorizace opravňuje celý fyzický výpis. |
| Historický bank pohyb v objednávce | Order read, jen přiřazená data a bezpečná metadata | Viditelný i bez bank služby; nedává právo číst celý účet, další unit ani účet spravovat. |
| Policy settings | Scope policy-management permission | Přepínač bank zůstává viditelný správci politiky; bez seznamu účtů a bez implicitní bank activation. |

`get_bank_transaction_history(account)` dnes nemá unit context. Rozšířit jeho canonical vstup o explicitní unit a ověřit uložený link i obě authority; původní account-only alias v přechodu smí pouze jednoznačně odvodit způsobilý linked scope, jinak fail closed, nikdy důvěřovat poslednímu UI scope. Kontrahovat po migraci callers. Účet sdílený s enabled unit se nemaže, neodpojuje ani nezastavuje BankSync; disabled unit z něj nezíská authoring práva. Pokud není žádný enabled oprávněný scope, běžný celý výpis není dostupný, order historie a servisní ingest ano. Nepřidávat ad hoc filtrování celého fyzického výpisu podle unit: unpaired pohyb nemá důvěryhodnou unit a filtrování by vytvářelo falešnou bezpečnost.

### 4. Jeden kontrakt platební prezentace pro e-mail a náhled

Sdílený assembler prezentace pracuje s uloženou metodou objednávky, finančním stavem, jazykem/tónem a serverovým rozhodnutím o povolené další akci. Bankovní a externí adaptéry dodají pouze své instrukce a bezpečné akce. Eligibility rozlišuje `collect_payment`, `bank_refund_instruction` a neplatební potvrzení; nepřebírá slepě checkout availability ani nepoužije záporný zůstatek jako univerzální bankovní refund. Návratové QR patří admin refund operaci, nikoli automaticky zákaznickému potvrzení. Nepředpokládá, že všechny konektory jsou platba kartou. Použije existující registry, `_shared/payments/email.ts`, `orderEmailPresentation.ts` a mechanismus bezpečných odkazů; nepřidává druhou frontu ani samostatný renderer pro každou bránu.

| Obsah/proměnná | Bankovní objednávka s povolenou akcí | Externí konektor | Bezplatná/uzavřená objednávka |
|---|---|---|---|
| `amount`, měna, symbol objednávky, `fullOrder` | Z finančních dat | Ze stejných finančních dat | Skutečný stav, žádná výzva k úhradě |
| `balanceReasoning`, `paymentDetails` | Instrukce k převodu | Metodově a stavově správný text, bezpečná další akce | Text o zaplacení/stornu/refundu/sporu dle stavu |
| `accountNumber`, `iban`, `variableSymbol` | Jen skutečné bankovní údaje a VS/RF podle měny | Nedostupné; žádný fallback ani reference vytvořená kvůli šabloně | Pouze výslovný historický kontext, žádná nová platební instrukce |
| Nový blok `paymentAction` | Jen pokud existuje povolená akce | Odkaz pro pokračování v podporované otevřené platbě | Prázdný |
| Nová obecná `paymentMethodName` | Lokalizovaný název převodu | Název podle descriptoru konektoru | Název uložené metody, bez výzvy |
| Platební QR/příloha | Pouze validní přímý převod a kladný splatný zůstatek | Žádné SPD/EPC, žádná příloha `qr-payment` | Žádné |
| QR vstupenky/PDF/wallet | Podle existujících admission/delivery pravidel | Stejná pravidla | Beze změny pravidel |

`paymentAction` je rezervovaný HTML blok skládající se v delivery rendereru. Privátní pay token se nestane obecnou editovatelnou textovou proměnnou, nepatří do veřejné projekce ani trackovaných URL. Ponechat dosavadní aliasy pouze na pojmenované hranici kontraktu. Pokud `balanceReasoning` už obsahuje akci a šablona použije nový blok, vložit ji právě jednou podle stejného completion mechanismu.

Připomínky: fronta plánuje jen metodu s podporovanou reminder akcí a platnou splatností. Příprava i předodesílací gate znovu ověří stav, politiku a podporu akce. Zaplaceno/storno/expirace/spor/refund nesmí skončit novou výzvou. Zálohové připomínky pouze pro metody, které zálohy skutečně podporují; neposilovat podporu Stripe/Barion pouhou změnou textu.

Změna politiky zneplatní budoucí neodeslané platební výzvy v dotčeném scope, včetně připravených snapshotů podle existing queue fences. Snapshot se nepřepisuje při retry. Zprávy, které překročily předodesílací hranici nebo už byly odeslány, nelze odvolat; jejich audit se zachová. Potvrzení, zaplacené vstupenky a neplatební zprávy se nezastaví plošně.

Editor nabídne proměnné podle metody/scénáře a zobrazí nekompatibilitu draftu. Samotné prázdné nahrazení IBAN nestačí: vlastní šablona může mít pevný text nebo vložený bankovní QR obrázek. Při aktivaci externího-only scope provést read-only audit efektivního body i wrapperu přes globální/tenant/unit/occasion dědičnost. Systémové defaulty měnit jen při shodě původního obsahu; cizí vlastní šablony nepřepisovat. Nekompatibilní vlastní obsah vyžaduje explicitní opravu/override před otevřením prodeje. Detektor pevných instrukcí je podpůrný, nemůže zaručit porozumění libovolnému HTML; zaznamenat schválenou revizi šablon. Překlady a generované náhledy musí odpovídat skutečné metodě, měně a jazyku, bez bankovních příkladů u Stripe.

## Implementační vlny

### 1. Canonical policy a bezpečný přechod dat

Změny: nový SQL vlastník politiky v `database/functions/payment_providers/`, scoped tabulky/RLS/ACL, resolver a receipted command/preview; rozšíření stávajících operation predicates a capabilities. Jeden explicitní forward migrační manifest/assembler podle současných payment operations. Neměnit historické zmrazené migrace.

Migrace: inventarizovat tenant/unit politiky, `DEFAULT_FORM_PAYMENT_METHOD`, Stripe unit features, uložené formuláře a známé global provisioning vstupy. Backfill zachová historicky povolené funkce, nikoli každému tenantu automaticky aktivuje každý instalovaný konektor. Global a další scope přepínat do zákazu až po preflightu dopadů a revizním potvrzení, bez plošného požadavku vynulovat finanční závazky. Nejasné řádky vypsat jako blocking report; nehádat default. Existující preferenci přeložit jednou, zrušit druhé vlastnictví defaultu.

Ověření: nové SQL testy dědičnosti, neznámé metody, tenant/unit scope mismatch, RBAC, stale revision, replay po odebrání práv a migrace fixtures starého stavu. Výstup: každá metoda má jedno autoritativní rozhodnutí a chybějící policy po backfillu fail closed.

### 2. Všechny serverové vstupy respektují politiku

Změny: `registry.sql`, `configuration.sql`, `builtin.sql`, `form_creation_domain.sql`, setup `drafts.sql`/`finalize.sql`, form save/settings/copy, `eshop/finalize_ticket_order.sql`, `ensure_order_payment_instructions.sql`, payment operation/checkout/connection commands a účtové authoring readers. Ze sdíleného resolveru odvodit setup recipients, bank accounts a e-mailové authoring accounts. Pro zakázanou banku nevracet výběry účtů.

Finanční seams: `operations.sql` (preview, command, correction/cancel, receipt replay), `operation_contexts.sql` (methods a request actions), `builtin.sql` (binding/readiness), `refund_dispatch.sql` (sales-independent servicing), `eshop_transactions/{add_transaction_to_payment_info_ws,remove_transaction_from_payment_info_ws,delete_manual_transaction_ws,insert_manual_transaction,get_transactions_for_order_all_available}.sql` (přímé guardy). Změnit uživatelské pairing/repair vstupy, nikoli přesměrovat `apply_transaction_pairing`, `match_bank_transaction` nebo `bank_settlement.sql` do nového enginu. Stávající cash correction bez requestId musí rovněž odmítnout gateway order a ověřit původ konkrétního opravovaného pohybu; korekce při disable nesmí sloužit jako nový cash receipt. Nepoužívat klientské actor_kind nebo evidence jako autorizaci.

Ohraničená dohledávka: od existujících callers těchto vlastníků dohledat operator orders, seat orders, duplication, MCP `forms.paymentOptions`, unit bank management a hluboké routy; seznam uzavřít tabulkou entrypoint -> společný guard -> test. Žádný writer nesmí přijmout klientské `enabled=true` ani rekonstruovat tenant z cizího form ID.

Neprovádět tiché mazání uloženého bankovního příjemce; pro zakázaný scope je neaktivní, běžný editor jej neserializuje zpět jako novou volbu. Rozpracované koncepty vyžadují explicitní nápravu. Otevření placeného formuláře bez dostupné metody se odmítne; bezplatný formulář nevyžaduje připojení brány.

Ověření: rozšířit `database/tests/payment_providers/{projections_configuration,setup_and_revision,connector_contract}_test.sql`, přidat přímé záporné RPC testy a souběh policy disable versus objednávka/intent. Výstup: zákaz nejde obejít starým klientem, MCP, kopírováním ani souběhem; incoming historické finanční fakty stále fungují.

### 3. Finanční projekce, Flutter, veřejný web a správa metod

Změny: payment descriptors/config/options v `packages/festapp_core`, `lib/components/payments/payment_editor_registry.dart`, unit settings, setup page/story/bank account, forms settings, bank navigation a email authoring provider; web `form_payment_options.js`, picker/result/overview a bank details. UI čte jednotné projekce a capabilities, nikoli lokální seznam tenantových výjimek.

V tenant/unit nastavení zobrazit jeden seznam instalovaných metod s povolením, dědičností, připraveností a příslušným onboardingem podle oprávnění. Zakázaná bankovní služba nemá běžné volby účtu ani správní routu; historický detail objednávky zůstává čitelný podle stávajícího oprávnění. Uživateli s právem správy politiky zůstává samotný přepínač metody, aby ji mohl znovu povolit. Gateway settlement/payout account neplést s bankovním převodem.

Finanční změny: `get_transactions_for_order.sql` skládá bank/cash pohyby a registry provider movements do jednoho čtecího DTO s discriminator původu a stabilním source ID, bez přesunu ledger dat. Sdílet totals/context s bulk ownerem; nevytvořit N+1 capability dotazy pro grid. `transactions_dialog.dart`/`TransactionModel` nesmějí předpokládat bank account u provider row. `order_payment_bank_options.dart` čte pouze explicitní bank actions, nikoli bankState=absent odhad. `payment_operation_flow.dart`/`payment_operation_dialog.dart` a modely actions/context konzumují purpose projekci i po reloadu/replay; odstranit syntetické přidání bank a inference bank z neprázdných instructions. Gateway request nikdy nedostane bank picker/payload ani cash correction. Request history zůstává zobrazitelná i bez `canRefund`; read-only recovery nesmí být blokována vstupním tlačítkem pro nový refund.

Migrace: odstranit bank fallback při chybějící projekci v Dart/JS, lokální default bankEnabled=true pro nové/resetované konfigurace a nezávislé provider visibility výpočty. Chybějící projekce znamená loading/error, ne banku; explicitní prázdný seznam znamená žádnou dostupnou metodu.

Ověření: cílené core/Flutter a web testy pro disabled tenant, disabled unit, enabled sousední unit, jediný Stripe bez pickeru, chybějící kontext, přepnutí scope a přímou routu. Změna role/kontextu okamžitě vyčistí odvozené capabilities a pozdní odpověď ze starého scope je neobnoví. Výstup: žádné nové bankovní volby v disabled scope a žádný zásah do jiného tenantu/unit.

### 4. E-maily a QR používají společnou prezentaci

Změny: `_shared/orderEmailPresentation.ts`, `confirmationContent.ts`, `payments/email.ts`, `emailRenderer.ts`, `ticketEmail.ts`, waitlist render context/renderer, setup/authoring preview a confirmation/reminder/paid/update/storno handlery. `queue_payment_reminders.sql` a existing email eligibility/send fences přijímají rozhodnutí stejného vlastníka. `qrCodePayment.ts` má explicitní bank guard i při přímém volání; nestačí důvěřovat každému calleru. Bank refund QR z payment operations sdílí policy/action rozhodnutí: `operationHandler.ts` dekoruje jen serverem oprávněný `bank_refund_instruction` s bank verification a immutable source binding. `instructions` pole samo nestačí; gateway payload se odmítne/odstraní i při chybě starého serverového response. SQL read/preview/replay nesmí vydat runnable instructions při disable, po settlementu/cancel nebo bez aktuálních práv. QR algoritmus zůstává SPD/EPC, USD pouze skutečné manuální instrukce při povolené akci.

Kontrakt: upravit `packages/festapp_contracts/email-variables.json`, regenerovat TS/Dart a preview examples společně. Zachovat `balanceReasoning`, `paymentDetails` a staré bezpečné aliases s přesně popsanou dostupností; vložit metodově obecnou akci jen jednou. Inventář QR callers rozdělit podle účelu, otestovat zákaz platebních QR a zachování vstupenkových/login/wallet QR. Prověřit Fakturoid a externí attachment hooky: nesmějí vytvořit paralelní bankovní výzvu; povolit je pro online-only až po ověření podporovaného kontraktu.

Ověření: renderer a queue testy skutečných produkčních handlers přes registry pro bank CZK/EUR, cash, Stripe, sandbox Barion, unknown connector, nulovou cenu, paid/partial/expired/refunded/disputed/action_required. Mock konektor se jménem bez slova card dokládá obecný text bez bankovních údajů. Ověřit předmět/body/wrapper, přílohy, retry snapshot, stale queue, přípravu po zákazu a duplicitní CTA. Výstup: žádné bankovní instrukce ani QR pro externí platbu a úplné, srozumitelné zprávy/náhledy v podporovaných jazycích.

### 5. Kontrakce a připravenost k samostatnému release

Přesunout všechny konzumenty na canonical policy; po inventarizaci podporovaných klientů odstranit Stripe unit feature jako druhý zdroj povolení a `DEFAULT_FORM_PAYMENT_METHOD` jako nezávislý runtime výpočet. Pokud je nutný dočasný veřejný adaptér pro vydané klienty, musí delegovat novému vlastníkovi, mít uvedený consumer a podmínku odstranění. Zachovat connector runtime sales policy, obchodní aktivaci a reálné readiness gates - nejsou duplicitou tenantového povolení.

Forward instalovat ve dvou kompatibilních krocích: nejprve nový vlastník a staré endpointy delegující do něj, potom klienti/renderery, nakonec contraction starých writerů/tabulek. Finální zákaz Global aktivovat až se všemi konzumenty a queue fences; starý renderer by jinak mohl znovu vydávat instrukce. Produkční pořadí a SQL deployment jsou samostatný autorizovaný úkon.

Ověření: canonical source parity, migration upgrade fixtures, cílené SQL/Deno/core/web checks a affected CI mirror lanes. Výstup: jedna cesta povolení, žádný nový provider-specific boolean, hotový migrační a rollback postup, doložená matice níže. Aktualizovat `docs/architecture/payment-providers.md` a příslušné existující README, nevytvářet paralelní architektonickou dokumentaci.

## Odstranění a výslovně zachované hranice

| Artefakt/chování | Cílový stav a důkaz |
|---|---|
| Chybějící payment options -> bank v JS/Dart | Odstranit; test chybějící projekce bez nabídky banky. |
| Nový/resetovaný payments config -> bank true | Nahradit scoped defaultem; test create/reset/copy/wizard/MCP. Historický decode jen pojmenovaná migrační hranice. |
| `DEFAULT_FORM_PAYMENT_METHOD` a Stripe unit feature jako druhá politika | Migrovat a odstranit runtime čtení; scoped search + migration parity + test starého klientského adaptéru, pokud zbývá. |
| Bankovní else větev pro libovolnou jinou metodu | Nahradit registry prezentací; unknown provider fail closed bez platební výzvy. |
| Samostatný výběr účtů bez kontroly scope | Všechny authoring readers delegují policy; přímé RPC/routa testy. |
| UI syntetická bank položka, bank odvozená z `instructions` | Odstranit; serverový seznam purpose-specific capabilities; cash a gateway negativní widget test. |
| `historyAccounts` všech admin účtů v order DTO a bankState-only tipy | Odstranit nesouvisející seznam; bank actions pouze pro způsobilý zdroj/scope. Gateway finance zůstává funkční. |
| Account-only history RPC | Migrovat na explicitní linked unit context; úzce omezený dočasný delegující adapter, následně drop starého signature/grantu a migration callers test. |
| Order transaction DTO omezené na bank/cash | Převést na source-discriminated reader existujících ledgerů; žádná nová finanční tabulka, žádné přepisování provider facts. |
| Unfiltered instructions v request history/receipt replay | Zachovat immutable interní audit; veřejný výstup znovu vyhodnotí action eligibility. Lost-response retry neopakuje peněžní side effect. |
| Form/sales enabled jako univerzální refund gate | Nepřidávat; test refundu staré gateway platby při zakázaném prodeji a odstraněném form selection. |
| Existující bank účty, reference, ledger, přijaté pohyby | Zachovat kvůli historii a late settlement; test zakázaný scope přijme skutečný starý pohyb. |
| Connector vlastní SDK, účty, runtime a sandbox gates | Zachovat jako technickou/provozní readiness. Žádné nahrazení booleanem policy. |
| Vydané Stripe URL/endpoint aliases | Zachovat jen stávající protokolovou hranici do stejného enginu; tento úkol je nepřepisuje. |
| Odeslané/připravené email snapshots | Audit zachovat; neodeslané nepřípustné platební akce zablokovat queue fence, nikoli přepsáním snapshotu. |

## Akceptační matice a ověření

1. Tenant bank=false, unit inherit/true, form bank=true, platný bank account: žádná volba/QR/nová reference; přímá objednávka i authoring RPC odmítnuty.
2. Tenant bank=true, unit A=false a B=inherit: A bankovní službu nepoužívá, B funguje. Sdílený fyzický účet dál synchronizuje skutečné pohyby.
3. Global s připraveným a provozně aktivovaným Stripe: nový formulář, wizard, kopie a MCP bez bankovní služby; objednávka -> checkout -> verified settlement -> e-mail -> platná vstupenka.
4. Stejný scope bez připojeného/ready Stripe: onboarding je dostupný oprávněnému uživateli, placený prodej zůstává zavřený, žádný fallback na banku.
5. Zakázaná či neznámá metoda, cizí unit, odebrané právo, starý snapshot/replay: fail closed; veřejný read nevrací soukromé zdroje.
6. Vypnutí s dluhy/pending refundy vyžaduje potvrzený aktuální impact preview, nezruší je. Souběh nevytvoří novou collection/instruction za hranicí zákazu; existující i nový oprávněný gateway refund staré platby funguje bez formSelected/new-sales. Connector write kill-switch ponechá jen read recovery nejistého zápisu.
7. E-mailová matice z vlny 4 včetně vlastního wrapperu, pevných bankovních textů a queue retry; ticket QR/login QR nezmizí.
8. Návrat policy na enabled neotevře automaticky zavřené formuláře, nevzkřísí staré výzvy a nezmění metodu existující objednávky.

9. Gateway order při bank enabled i disabled, uživatel se všemi bank rolemi: finance a provider facts viditelné; žádné historyAccounts, pairing/cash correction/bank refund/QR. Přímé RPC s podvrženým method/request/source odmítnuty.
10. Bank disabled: uložený pending request a rezervace zůstávají, QR a recipient picker zmizí i při reopen/replay; bezpečný cancel funguje pouze s pravdivým `transferNotSubmitted`. Opožděný debit se započítá, i když převyšuje očekávání.
11. Cash a bank offline cross-method kontrakt: skutečná cash refund bank objednávky podle cash policy; cash-only bez original bank identity nemá bank refund. Přesná korekce zachová audit a nesmí obejít zákaz nového receipt nebo gateway source.
12. Sdílený účet A disabled/B enabled: A order historie bez výpisu; explicitní B account view jen s jeho skutečnými bank oprávněními; spoofed B bez linked role odmítnutý. Ingest a matching historické A reference pokračují.
13. Bank/Stripe/Barion/unknown ledger: received/refunded/net/held/pending odpovídají existujícím totals; žádný refund intent se nevydává za settlement; neúplná fakta nejsou nula; opakované/excessive debity a disputes nezmizí z historie.
14. Konektor podporující příjem a refund observation, ale bez refund write: platba a verified externí refund fungují, spustitelná refund akce chybí, podvržené preview/command/replay nevytvoří intent, rezervaci, QR ani bank/cash fallback. Přidat kontraktový test s ne-Stripe konektorem, aby řešení nešlo splnit výčtem názvů bran. Full-only refund konektor dovolí správnou plnou částku a odmítne částečnou; supported-but-not-ready vrací jiný důvod než unsupported.

Konkrétní finanční validation seams: rozšířit `database/tests/payment_providers/{payment_operations,bank_refund_contract,refund_provider_dispatch,cash_command_guards,cash_history_access,order_read_bulk,order_read_plan_cache}_test.sql`, `database/tests/eshop/transactions/{payment_pairing_contract,unpaired_transactions,remove_transaction}_test.sql` a `database/tests/eshop/payment_operations_concurrency.test.mjs`. Ověřit bulk plán bez nového per-order policy/RBAC query násobení. Edge: `_shared/payments/{operationHandler,refunds}_test.ts` pro source/purpose QR guards, stale replay a sales disable versus connector write disable. Flutter: existující payment-operation/transaction test roots dohledat scoped `rg --files test packages/festapp_core/test | rg 'payment|transaction'`, doplnit assertions na nepřítomnost bank actions i na přítomnost gateway ledgeru; žádné golden testy překladu. Canonical migration parity: `python3 automation/assemble-payment-operations-migration.py --check`; aktuální manifest `automation/payment-operations-migration.json` a jeho frozen/superseded pravidla jsou východiskem, historické instalované migrace neregenerovat. Pokud aktuální forward již byl instalován v cíli, nový forward s výslovným ownership manifestem, nikoli změna aplikované historie.

Při implementaci použít dokumentované SQL testy nad disposable DB (`node web_client/scripts/run_db_tests.js <test.sql>`), relevantní Deno testy s oprávněními podle jejich importů, pnpm 11.24.0 pro web a targeted core/Flutter checks. Před Flutter úlohou ověřit workstation slot, testy vždy `--concurrency=1`. Validaci batchovat podle souvislých vln. Generovaný kontrakt ověřit `python3 automation/generate_email_variables.py --check`; preview generator použít podle jeho podporovaného CLI. Před source publication vyžadovat affected lanes `automation/test_ci.sh` z `CONTRIBUTING.md`; výběr odvodit z konečného diffu. Nenasazovat na základě pouhého cíleného testu.

Pokud bude potřeba browser ověření, delegovat Terra podle AGENTS.md, izolovaná background session, muted, light mode a lokalizovaná data. Psaní tohoto plánu nevyžaduje browser ani běh testů.

## Upřesnění při realizaci

Aktuální schema vyžaduje method identity i pro bezplatný registrační řádek bez bank account, reference a jakékoli collection akce. Ponechává se úzká existující `no-money registration` hranice ve finalizeru pro nulovou cenu (včetně vybrané, ale neúčtované hosted metody); jejím consumerem jsou vydané order/ticket/email kontrakty vyžadující payment_info. Nejde o povolení bankovní služby ani nabídku banky. Pro placený checkout chybějící metoda vybírá pouze jedinou explicitně dostupnou metodu, jinak je odmítnuta. Odstranění no-money storage identity patří samostatné migraci na nullable/no-payment kontrakt; tento úkol nesmí kvůli bezplatné registraci vyrábět gateway connection nebo bankovní reference. Ověření musí prokázat disabled-bank free checkout bez účtu/VS/QR.

## Rizika, předpoklady a provozní hranice

- **Předpoklad:** „organizace“ zde znamená tenant `public.organizations`; uživatel výslovně doplnil i samostatnou úroveň `units`. UI musí názvy jasně odlišit.
- **Rozhodnutí:** zákaz tenantu je nadřazen unit. Nejde o globální customer-specific seznam podmínek v klientovi ani o nové RBAC právo, které samo aktivuje konektor.
- **Rozhodnutí:** sales disable neodstraňuje závazky ani neblokuje gateway servicing. Bank service disable zakazuje novou/reopened bank instrukci; finanční facts/recovery, bezpečné zrušení neodeslaného bank requestu a přesná cash correction zůstávají samostatné. Nová bank výplata za trvajícího zákazu není autorizována skrytým recovery režimem.
- **Neověřeno:** živý Global tenant, jeho runtime policy, otevřené objednávky a vlastní šablony. Před provozním krokem identifikovat tenant přes canonical activation a provést scoped preflight přes schválený backend přístup. Provisioning skript není dovoleno slepě spustit znovu nebo upravit jeho identity assertion pro jinou DB.
- **Riziko:** pracovní strom obsahuje souběžné platby/email/auth změny. Implementace musí před první editací zkontrolovat aktuální diff dotčených vlastníků a aktualizovat faktické premise tohoto plánu; nesmí přepsat cizí rozpracovanou práci.
- **Release/rollback:** additive schema -> delegující backend -> klienti/renderery -> scoped aktivace -> contraction. Rollback po aktivaci zákazu nesmí vrátit backend/renderer s implicitním bank fallbackem; v takovém případě pozastavit dotčený placený prodej a opravit vpřed. Žádné mazání finančních faktů. Funkce deploy dodržuje pause/drain email queue a canonical restart dle `ai_context.md`.
- Neexistuje blocker pro lokální implementaci. Produkční změny, live connector aktivace a skutečné platby jsou samostatný rozsah. Realizace nyní autorizována pouze lokálně dle execution promptu; průběžná evidence je v payment-method-policy-RESULT-2026-11-12.md.

Jedna adversariální kontrola nad současnými vstupy odhalila a do vln zapracovala: order reader nesouvisejících účtů, syntetickou bank položku, QR dekoraci bez purpose, instruction replay, correction větev mimo běžný capability výběr, account-only history scope a chybné ztotožnění sales disable s finančním servicing. Původní plošná blokace vypnutí je nahrazena operation-specific pravidly výše. Testy ani živá data se při tvorbě plánu nespouštěly/nečetly.

Hotovo znamená jednotného vlastníka politiky pro každou metodu, prokazatelný zákaz ve všech veřejných i administrátorských vstupech, správnou komunikaci bez bankovních instrukcí u externích plateb, purpose-specific transakční operace bez bankovních nástrojů u gateway a zachovanou úplnou finanční historii/recovery i vstupenkové QR. Dokončení plánu ani lokální implementace samo nepotvrzuje produkční aktivaci.

Při závěrečné dohledávce zůstává released `delete_manual_transaction_ws` pouze protokolovým adaptérem pro vydané klienty: deleguje deterministický exact-source command a zachovává původní cash pohyb s opačnou auditovanou korekcí. Nemá samostatné mazání ledgeru a odmítá gateway source. Podmínka odstranění je ukončení podpory těchto vydaných klientů. Historické nulové ticket/wallet objednávky mohou mít chybějící payment_info; collection resolver pro ně vrací no-action, aby bankovní politika neblokovala neplatební QR. Placený chybějící payment identity nikdy nevytváří bank fallback.

Při ověření Barion sandboxu je veřejná nabídka metody záměrně `available=false`, ale již schválený privátní sandbox intent musí umět projít technickou collection eligibility. Registry projektuje `collectionAvailable` ze stejné dostupnosti nebo z explicitního privátního gate vlastněného konektorem. Barion vyžaduje enabled původní connection, shodný org/unit, uložený form binding a sandbox allowlist. Common policy/template/source/lifecycle guardy platí dál; tato projekce nesmí aktivovat veřejný prodej. Lokální recorded-protocol test dokazuje odmítnutí při technickém i produktovém zákazu a pokračující observation/refund facts po zákazu.

Architektonické upřesnění po realizaci: policy/template fence a monotónní epoch jsou explicitní součástí autorizovaných template/banner save/reset RPC. Žádný doménový trigger není povolen; technická výjimka platí pouze pro last-updated metadata. Přímé API DML nad email_templates/email_wrappers je odebráno, privilegované custom-wrapper migrace musí volat stejný privátní write-scope owner ve stejné transakci.
