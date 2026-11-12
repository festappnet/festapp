# Payment method policy - realizační záznam

Stav: dokončeno a lokálně ověřeno včetně následné architektonické opravy bez doménových triggerů. Závazná konečná evidence je checkpoint18. Ověření standard. Rozsah pouze lokální; žádný commit, push, deploy, produkční migrace ani skutečná platba/refund.

## Výchozí stav a pokračování

Přečteno celé zadání, autoritativní plán, CLAUDE.md a ai_context.md. Výchozí tracked diff uložen v `.git/payment-method-policy-baseline/tracked.patch`, seznam untracked v sousedním `untracked.txt`. Cizí změny se zachovávají. Existující payment operations forward je frozen; použije se nový forward s vlastním manifestem. Existující disposable PG15 běží na portu 55432; před použitím bude ověřen marker.

Canonical seam: existující payment_providers registry a operations engine. Nový scoped policy resolver vlastní pouze produktové povolení a preferenci; registry support, RBAC, readiness a finanční fakta zůstávají samostatné. Kolekce a bank instrukce musí projít současnou policy, historie a verified ingest zákaz nevyužívají jako filtr peněz.

## Vlny

1. **Dokončeno:** canonical policy schema/resolver, scoped preference, RBAC, potvrzený aktuální impact preview/receipted command, audit a zachovávající backfill.
2. **Dokončeno:** server callers, checkout/authoring/replay, bank scope, source-bound correction a operation support/readiness. SQL114 a skutečné concurrency14 passed.
3. **Dokončeno:** source-discriminated ledger a zapojené tenant/unit/form UI, fail-closed Dart/JS, onboarding, stale/revoked context a přímá bank routa. Targeted widgets/modely i canonical client/navigation passed.
4. **Dokončeno:** společná email prezentace/variables/previews, immutable queue policy/template fences, attachments a purpose-specific QR. Actual production-handler30, SQL a ticket canonical passed; neplatební QR zachovány.
5. **Dokončeno:** additive + contraction migrace, explicitní frozen/superseded ownership, deletion ledger a dokumentace; fresh bootstrap, upgrade3 a všech8 affected canonical lanes passed. Produkční release není součástí tohoto výsledku.

## Akceptační matice

Ověřené executable pokrytí všech14 scénářů, včetně závěrečných canonical gates:

| Scénář | Konkrétní důkaz |
|---|---|
| 1 | `method_policy_test`, `policy_tenant_scope_test`: tenant zákaz, unit enabled neobchází, stale bank selection nedává available/QR/instructions. |
| 2 | `policy_tenant_scope_test`, `method_policy_test`: A disabled/B inherit, skutečný late bank debit se započítá. |
| 3 | `policy_global_stripe_journey_test`: Global canonical checkout -> private claim -> verified settlement -> queue -> accepted ticket/admission. `policy_tenant_scope_test`: nový closed form bez bank. Wizard/copy/MCP sdílejí serverové guardy; finální seat lane passed. |
| 4 | Global journey před connection: žádná dostupná metoda; policy widget retry/onboarding test. |
| 5 | `method_policy_test`, policy ACL, operation_support, operationHandler, policy widget generation test: scope, unknown, odebrané právo, replay a source/purpose spoof. |
| 6 | `payment_operations_concurrency.test.mjs` 14 passed; preview revision/impact, disable/instruction/checkout, template/send obě pořadí. `refund_provider_dispatch_test`, Global journey: servicing po sales disable, runtime write kill-switch. |
| 7 | `paymentPolicyEmailHandlers_test` production matice; `policy_template_audit_test`; `policy_recovery_queue_test`; ticket-edge canonical step prošel včetně ticket/login/wallet QR. Celá ticket lane passed. |
| 8 | recovery_queue test: re-enable neobnoví starý snapshot; checkout replay nemění metodu. |
| 9 | operation_support a cash facade tests: provider ledger ano, žádný pairing/historyAccounts/cash correction; přímý legacy RPC odmítnut. |
| 10 | method_policy a recovery_queue: rezervace zachována, replay bez instructions, cancel vyžaduje pravdivé transferNotSubmitted, excessive late debit je skutečný refund. |
| 11 | payment_operations/bank_refund/cash guards/recovery: cash na bank order podle samostatné policy, exact correction jednou s audit/source. |
| 12 | tenant_scope: explicit account+unit B role/link, spoof B bez role odmítnut. Ingest není policy filtr ledgeru. |
| 13 | Stripe payment_totals včetně dispute amount=null/heldAmount; order_read_bulk parity; source-discriminated Orchard payment/refund; ledgerComplete/invalidIdentity DTO a UI warning. |
| 14 | method_operation_support: ne-Stripe observation-only žádný write/intent/fallback; externě pozorovaný refund je vidět a započítá se; full-only odmítá partial, readiness má jiný důvod. |

Všechny uvedené scénáře mají lokální executable důkaz. Závěrečné canonical gates jsou úspěšné; podrobnosti a historická selhání/opakování jsou zachovány níže.

## Deletion ledger

| Nahrazená cesta | Výsledek / zachovaná hranice |
|---|---|
| Missing options -> bank v JS/Dart | Odstraněno, parser/picker testy vyžadují explicitní server projection. |
| New/reset payments -> bank true | Odstraněno; config reset false, server-created closed form dostává scoped preference. Historická absence materializována jednorázově v additive migration. |
| DEFAULT_FORM_PAYMENT_METHOD, stripe_unit_features | Runtime čtení odstraněno, contraction archive + DROP RESTRICT + JSON key removal; upgrade a fresh bootstrap důkazy. |
| Bank else pro libovolnou metodu | Explicitní metoda/registry presenter; unknown bez bank výzvy. |
| Unscoped account list/history | No-args picker a account-only statement signatures dropped; linkable(unit) a history(account,unit), skutečná unit role/link a policy. |
| Syntetická refund bank položka / instructions inference | Odstraněno, purpose+source+server eligibility; raw instructions nestačí. |
| historyAccounts / unrelated admin discovery | Odstraněno z SQL/Dart/widget/callers; standalone výpis jen z explicitního unit account. |
| Bank/cash-only order DTO | Reader spojuje existující ledgery, provider movements a dispute facts; žádná nová finance tabulka. |
| Raw replay instructions | Interní immutable receipt zachován; veřejná projekce znovu autorizuje a filtruje současné instructions/QR. |
| Form/sales universal refund gate | Není použit; original connector servicing má support/readiness/RBAC a write kill-switch. |
| Legacy delete_manual_transaction_ws | Zachován pouze released consumer RPC, deleguje exact-source canonical correction s deterministickým receipt; původní pohyb se nemaže. Odstranit až po ukončení podpory released klientů. |
| Bank účty/reference/facts/ingest | Záměrně zachovány kvůli historii a late/excess settlement, nikoli jako parallel policy. |
| Connector SDK/účty/runtime/sandbox | Zachovány jako samostatná technická readiness, policy je nenahrazuje. |
| Vydané Stripe URL/endpoint aliases a root projections | Úzké existující released protocol consumers, delegují stejný engine/policy; odstranit při ukončení podpory těchto vydaných klientů/URL, nikoli při tomto lokálním cutoveru. |
| Email snapshots | Zachovaný immutable audit; neodeslané platební akce mají aktuální epoch fence. |
| No-money registration | Jmenovaná hranice v plánu, released order/ticket/email consumers. Nulový checkout bez bank reference/attempt; historický řádek bez payment identity vrací no-action a neblokuje neplatební wallet/ticket QR. |
| Floating cash RPC a legacy payment metadata aliases | Zachované released protocol signatures delegují stejné owners, nepovolují policy fallback; nullable reset je false. Odstranit s ukončením příslušných released klientů. |

## Evidence

Závěrečné i průběžné důkazy a opravy jsou v checkpoints níže. Logy `.git/payment-method-policy-baseline/`. Starší checkpoints popisují tehdejší rozpracovaný stav; závazný finální výsledek je checkpoint18. Produkce nezměněna.

## Checkpoint 1

Implementováno (dosud ne úplné vlny): `method_policy.sql` vlastní scoped tabulky, fail-closed resolver, typed management predicate, impact preview s potvrzením aktuální revize, receipted command a privátní audit. `operation_support.sql` odděluje refund write support, partial support, observation a runtime switch. Nový forward `20261112160000_payment_method_policy.sql` a manifest/assembler; frozen historie beze změn.

Zapojení: registry collection/setup availability, finalizer policy fence, bank instructions owner, bulk operation context s jedním načtením policy na distinct unit, request purpose/source/eligibility, receipt replay re-projection, pairing/unpairing, cash source guard a exact correction guard. Client missing options fail closed. Odstraněna syntetická bank refund položka a inference z instructions; Edge vyžaduje explicitní aktuální purpose/source eligibility. Order DTO nevrací historyAccounts a bank setup/access používá explicitní server flags. Account statement nový signature (account, unit), původní signature drop; caller přenáší unit.

Důležité: role-only predicates nebyly spojeny s product policy, aby zůstala dostupná bezpečná bank cancel/cash correction při disable. Bank policy se kontroluje v authoring/operation boundaries. Finanční ledger/ingest zůstává původní.

Lokální DB: `festapp-payment-policy-20261112`, port 55452; vlastní config `/tmp/festapp-payment-policy-20261112/supabase/config.toml`. Bootstrap prošel baseline + všechny aktuální forwardy; marker ověřen. Původní port 55432 měl starší schéma a nesouhlasící migrační ledger; nebyl resetován. Pokus o upgrade odmítl Supabase CLI před aplikací migrations (missing 20261109133000/170000/190000). Toto není blocker nové disposable DB.

Ověřeno:
- Deno `deno test --allow-env supabase/functions/_shared/payments/operationHandler_test.ts`: 6 passed, 0 failed. Log `.git/payment-method-policy-baseline/edge-wave1.log`.
- SQL runner na portu 55452: `method_policy_test.sql`, `payment_operations_test.sql`, `bank_refund_contract_test.sql`: 3 passed, 0 failed. Log `.git/payment-method-policy-baseline/sql-wave2.log`. Test obsahuje unit disable vs enabled sibling, unknown/missing policy, scope mismatch, stale preview, revoked replay, raw instruction removal při replay, retained reservation a excessive verified late debit.
- Následně změněny cash a account-history boundaries; tyto poslední změny ještě nejsou pokryty opakováním relevantní SQL batch.

Otevřené nejbližší kroky: ledger source-discriminated rows; další authoring/deep RPC guards a společné locking pořadí; policy settings ve skutečných tenant/unit screens; preference/default cutover a Stripe feature contraction; email assembler/queue fences/reminders/QR/contract/templates; acceptance 1-14, concurrency, upgrade/source parity, targeted client/web a affected canonical CI lanes. Goal nadále active, žádná vlna neoznačena kompletní. Produkce nezměněna.

## Checkpoint 2 - rozšíření přes všechny vrstvy (stále rozpracováno)

Nové/rozšířené chování:
- Policy řádky mají vlastní method/scope revizi; collection epoch není globální org revision, aby změna unit A nezneplatňovala unit B. Org lock writer bere exclusive, collection writer shared; policy command nebere order/payment/capacity/transaction zámky. Finalizer bere shared před form lockem, operation command před transaction/capacity/order/payment, queue send před capacity/order/message. Cash source correction bere transaction před capacity/order/payment. Zbývá konkrétní concurrency test disable vs kolekce a intent.
- Transakční reader spojuje existující ledger s registry movements; TS/SQL konektory přidávají sourceId, Dart model přijímá source/provider/sourceId. Žádná nová finanční tabulka. Gateway nemá bank picker/actions a přímá cash correction/receipt je odmítnuta i v shortcut větvi.
- Tenant i unit settings obsahují `PaymentPolicySettings`, běžný seznam metod s inherit/enabled/disabled a preferencí, načtením/chybou/retry a potvrzeným impact preview před zápisem. Starý Stripe toggle v unit settings odstraněn; serverový released Stripe feature endpoint nyní pouze deleguje policy, store zatím čeká na contraction. Nový widget dosud nemá browser/widget ověření a readiness/onboarding projekce se ještě doplňuje.
- Unit/form projekce obsahují canonical policy. Bank account picker SQL vrací prázdný seznam při disable, form/wizard cards přijímají showBank/showCash; RightsService bank navigation protíná server capability s unit policy. Oprávnění samotného policy settings zůstává nezávislé.
- `payment_collection_action_internal` je společný owner nových collection instrukcí pro e-mail a public order overview; kontroluje scope, method, životní cyklus, dluh, hold/identity, deadline a aktuální form availability. Public reopen nevrací bank QR/payload při disable; hosted pay action se skrývá.
- `get_order_details_for_email` projektuje collectionAction a providerPayment. Queue enqueue zachycuje collection action epoch; intent-valid/send znovu kontrolují aktuální povolení a epoch. Prepared snapshot se nepřepisuje. Reminder scheduler omezen podporovaným bank collection kontraktem. QR raster owner vyžaduje explicitní bank/collect_payment/allowed a kladnou částku, callers předávají rozhodnutí.
- Email kontrakt rozšířen o paymentAction/paymentMethodName a regenerován. Completion vkládá akci v body/wrapperu jednou; bezpečné aliases zachovány. Unknown/missing method již není implicitní bank větev. Generic hosted text neříká automaticky „kartou“. Preview generator teď explicitně deklaruje bank policy ve bank fixturech.

Evidence od checkpointu 1:
- `method_operation_support_test.sql` a `order_read_bulk_test.sql`: 2 passed. Ne-Stripe „orchard“ ověřuje observation bez write, side-effect-free odmítnutí preview/command, žádný cash fallback/correction, support vs readiness reason, full-only odmítnutí partial a povolení plné částky; source-discriminated provider row viditelný. Bulk test porovnává staré finanční hodnoty, nový purpose kontrakt samostatně; stále zakazuje scalar context v gridu.
- SQL celá `database/tests/payment_providers`: první batch 11/18, po migraci starých fixture assumptions 16/18; poslední dvě byly legacy registry-uninstallation FK a chybějící explicitní policy v druhém connector fixture. Opravy provedeny, projection test nakonec prošel v recovery batch; celá sada ještě musí být finálně zopakována na finálních zdrojích.
- `policy_recovery_queue_test.sql`: passed (poslední log `.git/payment-method-policy-baseline/sql-recovery.log`): disabled bank safe cancel, zákaz nového cash receipt, přesná audited cash reversal po disable a odmítnutí druhé reversal, queue epoch/fence a immutable audit, žádná resurrection po re-enable.
- Deno cílená sada orderEmailPresentation/confirmationContent/emailContentCompletion/payments operationHandler/refunds: **27 passed, 0 failed**, `.git/payment-method-policy-baseline/edge-wave4.log`.
- `deno check supabase/functions/_shared/emailRenderer.ts`: passed (`edge-check.log`), kontroluje i skutečné produkční handlers.
- Generovaný email kontrakt check passed, preview check passed **66 scenarios** (`preview-check.log`). Chybí ještě rozšířená metodová/stavová/handler matice a audit wrapper/pevného obsahu.
- Oba assemblery `assemble-payment-method-policy-migration.py --check` a `assemble-payment-operations-migration.py --check`: passed; `migration_forward_owners.py` obsahuje nový explicitní superseding manifest. Po posledních SQL změnách nutno opakovat finální parity.
- Targeted Dart analyze: bez compiler error, jedna nově vzniklá unused import opravena; existující info linty zůstaly. Poslední UI změny ještě neanalyzovány.
- Core test batch 11 passed/1 failed kvůli bank projection chybějící ve starém connector fixture; fixture opravena, nutno zopakovat jen dotčený core test.
- Web 7 passed/2 failed kvůli starému null->bank očekávání; testy aktualizovány explicitní bank projekcí, nutno zopakovat.

Test fixture změny jsou explicitní: payment_lifecycle a scanner fixture provisionují scope policy v test transakci, production nenabízí chybějící policy implicitně. Nový unknown/missing policy negative test zůstává. Cash history/ACL testy migrovány na account+unit signature a nepřítomnost unrelated account discovery.

Další práce musí pokračovat, goal active. Neoznačovat všechny vlny ani akceptační matici hotovými. Otevřeno: zbývající authoring readers/direct RPC/MCP/deep routes, bank service versus safe recovery kontrakty; reálné readiness/onboarding a scope-stale UI testy; ledger disputes a unknown completeness; moderní default/reset fixtures; Global Stripe fixture journey; email production handlers pro všechny metody/stavy/QR purpose a duplicate CTA, vlastní body+wrapper audit před online-only aktivací, Fakturoid/external attachment gate; concurrency, upgrade fixtures, security/source inventory, deletion ledger a docs; canonical CI mirror lanes podle finálního diffu. Žádný externí blocker nyní není. Produkce nezměněna.

## Checkpoint 3

Další implementace: všechny public hosted projections a přímé Stripe/Barion checkout claims znovu ověřují collection policy, claim fence je před order/capacity lockem. Refund servicing/reconcile/observation tyto sales guardy nepřebírají. Bank authoring management/list/link/user/banksync boundaries kontrolují skutečný enabled linked scope; opraveno, aby nové propojení účtu ověřovalo cílovou unit a nevyžadovalo již existující link.

HistoryAccounts a PaymentHistoryAccount odstraněny i z produkčního Dart modelu/widgetu/callers. Výpis je samostatná akce ze správy konkrétního účtu v unit a předává account+unit. Edge refund QR navíc ověřuje sourceMethod/sourcePaymentId a vazbu sourceOrderId na order envelope. Bulk context projektuje source identitu jednou v původní dávce.

Přidán revizní audit efektivních email body+wrapper přes existující inheritance resolver a explicitní review API/UI v nastavení formuláře. Detekované pevné bankovní instrukce vyžadují opravu; approval je nepřijme. Změna obsahu zneplatní review. Při bank-disabled hosted prodeji je nutný schválený aktuální čistý obsah. Žádné cizí šablony se nepřepisují. Zbývá finální souběh template authoringu, větší handler matice a Fakturoid/external hooks guard.

Migration backfill doplněn o odmítnutí neznámých historických metod; zachování služby při doložených linked bank účtech; explicitní Stripe override pro historicky hidden unit, aby enabled sibling omylem neaktivoval další existující unit. Aktuální StripeFeature.visible bere canonical policy; legacy root stripe_preview_enabled je jen serverový released-client adapter.

Ověření:
- Flutter `test/components/eshop/additional_payment_test.dart`: **10 passed**, log `flutter-payment.log`.
- Web picker/registry: **9 passed**, log `web.log`.
- Concurrency původní engine + nové policy races: **12 passed**, log `concurrency-policy.log`. Prokázán skutečný PostgreSQL lock: disable před refund instruction -> žádná rezervace; instruction před disable -> stale impact potvrzení se odmítne a vyžaduje nový preview; disable před public checkout -> rejected bez nové reference. Původní test generic negative correction migrován na skutečný released cash boundary, protože nový correct_record záměrně vyžaduje konkrétní source transaction.
- Scope/audit/connector SQL batch: **3 passed** (`sql-scope-template.log`): tenant zákaz nepřebije unit enabled, shared account enabled B vyžaduje jeho role/link a spoofed B je odmítnuto; body/wrapper audit+stale revision; connector fixture explicitně reviewuje čistý obsah.
- Přímý QR raster owner + Edge refund source/purpose + duplicate action completion: **10 passed** (`edge-qr-completion.log`). Vstupenkový/login/wallet QR callery tímto vlastníkem neprocházejí, jejich regresní testy ještě zbývají.
- Analyzer 3: žádné compiler errors; nově vzniklé warnings import/non-null assertion opraveny. Jedna kontrola se krátce překryla s Flutter taskem jiného worktree, který se objevil mezi kontrolou slotu a startem; další Flutter/Dart úlohy musí čekat na uvolnění slotu. Jiná úloha nebyla zastavena.

Upřesnění plánu: nulové registrace mají existující bank-shaped payment_info storage identity bez jakékoli platební služby. Tato jmenovaná no-money boundary zachovává released order/email consumers; placený missing method nově vybírá jen jedinou skutečně dostupnou metodu, jinak PAYMENT_METHOD_REQUIRED. Přidán oddíl do autoritativního plánu. Potřeba dokázat free disabled scope bez account/reference/QR; nejde o implicitní bank collection fallback.

Otevřená práce nadále viz checkpoint 2, zejména Global Stripe skutečný lokální journey, volné registrace, migration backfill/upgrade+contraction, public config/defaults a všechny callers, affected CI lanes a dokončená matice/deletion ledger. Nejnovější změny SQL a poslední změny widgetů ještě čekají na finální validaci. Goal active, produkce beze změn.

## Checkpoint 4 - plný Global SQL journey a připravená kontrakce

- `policy_global_stripe_journey_test.sql` prošel společně s `eshop/stripe/create_order_test.sql`: **2 passed**, `sql-global4.log`. Global fixture má bank=false/preferStripe, onboarding bez ready účtu a žádný fallback; schválí čisté efektivní šablony, nastaví test-only ready runtime/connection, provede canonical checkout, privátní claim, session receipt, verified provider event/facts ingest, paid transition, queue intent a accepted delivery/admission. Dále dokazuje nový Stripe refund intent po sales disable bez deklarace settlementu a bezplatnou registraci bez ready connection/account/reference/QR. Žádné remote volání ani placená transakce.
- Existing Stripe SQL sada po migraci fixture store měla **11/12 passed**, poslední neúspěch byl dříve latentní explicit-free-Stripe constraint. Opraveno bounded no-money větví a oba dotčené testy prošly. Všechny staré INSERT stripe_unit_features v aktuálních testech/JS fixturech převedeny na canonical policy. Legacy setter vrací efektivní stav, ne zaslané přání.
- Contraction `20261112170000_payment_method_policy_contraction.sql` lokálně aplikována na portu 55452: zachovává původní config evidence v scope.migration_evidence, DROP legacy Stripe feature table RESTRICT, odstranění starého JSON defaultu. Dva forwardy a dva source seznamy má společný policy assembler. Nový provisioning Global zapisuje canonical policies pouze pro nově založený tenant, existující nesoulad odmítá preflight chybou, DB identity assertion nebyla oslabena.
- Po contraction nelze znovu přehrávat celý additive forward, protože historický backfill čte odstraněný store. Pro lokální vývoj byl použit `/tmp/festapp-policy-current-owners.sql`: sources z manifestu, pouze method_policy.sql od první CREATE FUNCTION (bez consumed backfill); vše transakčně na disposable 55452. Finální upgrade musí být nově ověřen bootstrapem obou forwardů, nikoli touto pomůckou.
- Moderní missing method placeného checkoutu vybírá jen jedinou dostupnou metodu. Nulový explicitní hosted checkout je po ověření uložené form selection převeden na no-money storage boundary, nikdy nepotřebuje provider identity a nevytváří pokus/reference. Payment policy data značí no_money_registration. Přímá volba nevybraného hosted konektoru na free form se odmítá.
- Deno renderer/QR/presentation/refund targeted sada: **29 passed**, `edge-methods2.log`. Preview generator prošel: **328 scenarios**; metadata a lokalizované popisy paymentAction/paymentMethodName doplněny do skutečného editoru.
- Core preview composition doplněna stejným one-action completion jako delivery. Provider/cash/closed preview account hodnoty jsou prázdné a withContext nesmí doplnit bank data do externí metody. Production hosted update/paid text používá společný status presenter a registry displayName; předložený token zůstává jen v trusted renderovaném action bloku. Fakturoid/external attachment hooky jsou při nepovolené bank collection potlačeny; hosted jde samostatnou původní registry větví.
- UI odlišuje canRefund od canViewHistory. Historie je čitelná bez nového write; bank disabled canCancel je dostupné bez instructions/QR (checkbox přesunut mimo instruction block). Raw/stale payload sám nikdy nezobrazí QR. **26 Flutter operation widget tests passed**, `flutter-operations3.log`.
- SQL defaults/regression po explicitních fixturech a bank none deadline correction: **2 passed**, `sql-defaults.log`.
- Source inventory/security deklarace se nyní aktualizují. Skript `/tmp/payment_policy_inventory.py` přidává pouze nové headers/signatures, nový account+unit signature a canonical source seznamy; první pokus před zápisem skončil na neregistrovaném již existujícím helperu, opraveno filtrováním explicitního seznamu. Běží/ověřit log `security-source2.log` (exec session 19495). Canonical source contract generován, ověření proti DB ještě zbývá.

Nejbližší zbytek: upgrade fixture z před-policy stavu a fresh bootstrap; účetnictví disputes/unknown DTO; úplná server/handler/queue acceptance matice včetně B scope a stale context; širší core/Flutter testy pro nové policy settings/editor; template review závody; operation inventories/ACL parita; affected canonical CI všech 8 lanes dle konservativního inputs.json (SQL/supabase + unclassified automation), browser lane podle AGENTS delegovat Terra až budou inputs final. Dokončit deletion ledger a architecture/README, uložit finální důkazy a pouze pak complete. Žádný externí blocker, goal active, produkce nezměněna.

## Checkpoint 5 - upgrade, čistá instalace a skutečné email handlery

- Upgrade ze zrekonstruovaných pre-policy vlastníků probíhá výhradně v logickém klonu označené disposable DB. `payment_method_policy_upgrade.test.js`: **1 passed**, `upgrade-policy-final.log`. Neznámý legacy default zastaví migraci před změnami; peněžní řádek byte-for-byte zachován; historicky hidden sibling neaktivován; Global stripe preference/bank=false; contraction zachovává evidence a odstraňuje staré tabulky/signatures/default.
- Čistý baseline + oba forwardy: bootstrap **passed** (`fresh-bootstrap.log`). Následné doplnění template authoring fence bylo aplikováno lokálně ze zdroje; finální bootstrap se ještě musí zopakovat pro tuto poslední změnu.
- Finální SQL provider/Stripe batch **34 passed**, source parity v témže batch nejprve selhala kvůli neregenerovanému testu po posledním source edit; po regeneraci parity **1 passed** (`sql-parity-acl.log`). Nelze z tohoto logu tvrdit ACL DB test: zadaná SQL cesta neexistovala. Skutečné security JS katalogy odmítly jiný port/PG15 podle vlastního guardu; žádný guard nebyl obejit, jejich vlastní fixture/gate ještě zbývá.
- `server_security_migrations.test.mjs`: **8 passed**, `security-source-final.log`; nové deklarace mají explicitní ACL. Nový trigger authoringu bude finálně součástí této deklarace.
- Production `renderQueuedEmail` + skutečné confirmation/update/paid/storno handlery, registry binding a inherited wrapper/completion: matice bank/cash/Stripe/Barion/ne-Stripe Orchard/unknown x 7 stavů x 4 handlery; žádné remote HTTP, snapshot recipient, žádné stale account/QR/hooks při zakázané kolekci, privátní token se neotevře; povolené hosted CTA je přes legacy/body/wrapper přesně jednou. Dále skutečné bank CZK/EUR/USD confirmation/update/paid/reminder; CZK/EUR attachment, USD jen manuální údaje. **1 matrix test passed**, `edge-production-handlers2.log`. Samostatný raster owner odmítá také USD QR.
- Ledger Stripe obsahuje dispute status facts se stabilním sourceId, heldAmount a amount=null, nikoli fake refund. Totals/report zachovány; payment_totals_test prošel ve 34 SQL batch. DTO/UI přenáší ledgerComplete a invalidIdentity, net nezobrazuje jako jistou nulu při neúplných datech, nullable date/amount nepadá.
- Impact preview doplněn o pending bank instructions, undispatched/dispatched/unknown provider intents a orders with obligations; žádný automatický cancellation. UI zobrazuje všechny kategorie, explicitní potvrzení je hash konkrétního snapshotu.
- Template changes mají org policy exclusive fence před zápisem; send/collection drží shared fence před order/capacity/message locks. Epoch zahrnuje aktuální efektivní template revision také pro bank. Revizní review není trvalé povolení po změně contentu.
- Concurrency znovu **12 passed**, `concurrency-policy-final.log`.
- Flutter rozšířený batch odhalil stale bank preview expectations a existující test assumption, že každá definice má fixture. Opraveny; policy settings widget testy nyní odhalily Null check uvnitř RPC klienta a probíhá cílená diagnóza, neprohlašovat UI gates za splněné. Nová policy generation/retry tests ještě nejsou green. Preview generator doplnil overview aliases pro nové hosted/cash scénáře; finální regenerace a test čekají.

Zbývají všechny finální klientské/Edge checks po posledních edits, authoring concurrency proof, source/ACL/inventory parity, deployment-independent canonical CI všech 8 lanes a acceptance/deletion ledger/docs. Browser lanes musí spustit Terra dle AGENTS; žádný agent zatím nespawnován. Goal active, bez externího blockeru, produkce beze změn.

## Checkpoint 6 - canonical gates a opravované historické fixtures

- Browser delegace Terra: `web-startup` **passed 57.7s**, `client-contract` **passed 41.6s**. `seat-checkout` ještě selhal v přípravě na dvou measurement fixtures bez explicitní bank selection. Po opravě helper provisionuje bank policy+scope a uložené payments; analytics patch už nemaže celou platební konfiguraci. Measurement SQL **6 passed** (`sql-measurement-policy.log`). Browser checkout část ještě neproběhla, bude opakována Terra po dokončení root ticket lane.
- Root canonical mirror: `image-contract` **passed3.4s**, `wix-checkout-compatibility` **passed9.5s**, `navigation-interactions` **passed58.7s**, `server-policy` **passed10.4s**, `ci-other-lanes.log`. Ticket lane postupně odhalila setup-preview, poté staré form-widget fixtures. Vzniklé assertion změny explicitně modelují server policy/selection; negativní missing-policy produkční kontrakt nebyl oslaben.
- Production setup preview nyní přenáší explicitní collectionAction a nemá missing-method -> bank. Authoring account vyžaduje skutečnou bank action; SQL vyžaduje selected bank a actual linked account. Targeted ticket-edge canonical step prošel se všemi čtyřmi Deno batch, včetně skutečných ticket/login/wallet QR. Po poslední drobné změně probíhá celé opakování ticket lane.
- Staré cash delete RPC bylo nalezeno při závěrečném bounded callers auditu. Nyní deleguje stejný exact-source receipted correction engine, zachovává původní cash fact. Gateway historický cash row přes tento RPC nelze změnit. Case-insensitive historický CASH type přijímá exact-source guard (`upper(type)`), nikoli slabší role/source kontrola.
- Rozšířený SQL batch: **47 passed/8 failed**; po aktualizaci explicitních policy fixtures a korekčních gross/net expectations transakční sada **16 passed/3 failed**, poslední tři cíleně opravené a **3 passed** (`sql-transactions3.log`). Celý finální batch ještě zopakovat po posledních SQL edits.
- Setup/copy sada **18 passed/4 failed**; po explicitní bank policy fixture a opravě no-payment collection readeru dotčené čtyři **passed** (`sql-setup-policy2.log`). Historický nulový wallet order bez payment_info nesmí být podmíněn bank collection; resolver vydá false/no_payment_identity, queue nejprve samostatně testuje, zda snapshot vůbec collection action měl.
- Finální concurrency **14 passed**, `concurrency-complete-final.log`; support/observation + source parity **2 passed**, `sql-observation-final.log`; upgrade nejnovějšího contraction **1 passed**, `upgrade-complete-final.log`; UI source detector **[]** (source-only, nikoli browser pixel audit). Security source **8 passed**, `security-source-final2.log`. Poslední edits vyžadují jen relevantní refresh, nikoli opakování všech již green nezměněných lanes.
- Jedna dočasná CI kolize byla skutečný globální mirror lock jiné session ve worktree festapp-ticket-brand-parity-20261112. Bylo vyčkáno, žádná cizí úloha nezastavena. Nejde o trvalý blocker.

Aktuálně běží targeted Flutter form/preview fixtures (`flutter-form-policy2.log`, exec93286). Chybný předchozí --plain-name s OR nespustil žádný test a není důkazem úspěchu. Před další Flutter úlohou ověřit slot; tests --concurrency=1. Canonical ticket lane je nyní failed a musí doběhnout green před dokončením. Poté Terra seat-checkout a zbývající final gates, snapshot ownership/deletion/acceptance audit. Goal active.

## Checkpoint 7 - MCP a konečné přímé boundaries

- Skutečný MCP `forms.paymentOptions` měl strict output parser bez nové policy a odmítal SQL response. Doplněn typovaný `paymentMethodPolicy`, org/unit identity, per-method invariant a zákaz bankAccounts/available při disabled. Missing policy ani credential extra keys nejsou přijaty. MCP unit kontrakt **8 passed**, docs regenerate/check **current** (193 tools/83 permissions). `forms-settings-postgres.test.mjs` včetně Global vytvoření+kopie+paymentOptions **20 passed** (`mcp-policy-postgres3.log`). SQL provider disabled projection doplnila explicitní recipient=null, aby se zachoval veřejný kontrakt.
- Test fixtures bank/cash jsou explicitní v `tools/festapp/test/form-fixtures.mjs`; reset očekává bank=false, lifecycle opening fixture vědomě volí cash s kompletní `payment_selection_intent=replace`. Přes stejný engine bez jiné default cesty. Reminders+deposit SQL **10 passed**, `sql-reminders-deposit2.log`.
- Canonical root mirror `server-policy` **8.7s passed**, `ticket-preview-and-delivery` **66.2s passed** (`ci-server-ticket-final.log`). Po následném malém FormEditorDraft/DbForms boundary editu nutno příslušný ticket-client vstup ověřit znovu. Sedm z osmi lane names má green důkaz; seat-checkout stále failed, browser checkout se nespustil.
- Seat retry nejprve odhalil stale ticket-layout readiness digest: canonical `can_read_orders` již měl body795b..., generovaný probe čekal6b8... . Přepočítán generátorem ze zdrojů a přidán do nového policy forwardu. Configuration PostgreSQL **15 passed** (`mcp-configuration-policy.log`). Frozen migrace se neregenerovala.
- Další seat retry došel na `assemble-access-membership-migration.py --check`, protože současný email_queue má nový policy owner. Přidán frozen digest historické access migrace a version-aware kontrola: nezměněné sources musí byte-match jejich starý block, pouze explicitní policy manifest smí supersedovat, všechny current function bodies musí být effective head. Default regeneration staré access migrace je odmítnuta. `assemble-access-membership --check`, policy/ops/config assemblery a security source **8 passed** (`security-forward-check.log`). Toto není bypass ani přepis staré migrace.
- Rozšířený authoritative SQL batch **72 passed/3 failed** (`sql-authoritative-final.log`): scheduler procházel legacy test scope s nesouladem hierarchy. Collection read nyní vrací no-action/scope_mismatch bez přerušení ostatních financial/queue facts; **nový checkout** musí explicitně projít full org/unit resolverem. Tři cílené regresní tests **passed**, `sql-scope-collection.log`. Celý finální batch a fresh bootstrap po těchto edits ještě zopakovat.
- Editor při disabled bank neodesílá bank_account ani nemaže historický příjemce (`toEditedJson`), po save přijímá aktuálně znovu autorizovanou read-only policy do nového draftu. Targeted form write/projection **25 passed**, `flutter-form-write-final.log`; model/widget/email batch **347 passed**, `flutter-final-model-widget.log`. Nejnovější jednorázové copy current policy ještě čeká na relevantní opakování.
- Analyzer14 files: **0 errors/0 warnings,27 info lints**, `analyze-final.log`; nejde o clean lint výsledek, většina infos je stávající style/async-context v těchto velkých souborech. Source detector vybral tři skutečné Dart UI soubory a vrátil `[]` (`ui-detector.json`); není to pixel audit.
- Deep bank destination nyní sleduje změnu rights/policy, znovu ověřuje skutečný current unit capability po await a při revokaci smaže načtený account. Původní bank warning/routes root **39 passed**, `flutter-bank-route-final.log`; nově přidaný policy-revocation assertion právě běží jako targeted destination test (`flutter-bank-revoke.log`, exec70265). Fixture explicitně poskytuje linked unit/bank policy a používá scoped management RPC.

Aktuální pending: targeted authoring boundary SQL (`sql-authoring-boundaries.log`), targeted bank revocation test, následný Terra seat retry (čeká na followup); root žádná jiná Flutter úloha. Potom full final SQL/upgrade/bootstrap, final ticket-client/form/core/editor checks podle posledních edits, source/operation inventory, dokončit receipts a status. Browser agent `policy_browser_gates` idle; používá fork none gpt-6.1-terra/low podle standing AGENTS. Žádný externí blocker, produkce beze změn, goal active.

Checkpoint 7 doplnění: bank destination revocation **2 passed**, authoring linked picker/email reader **1 passed** (`sql-authoring-boundaries2.log`; první přidaná assertion přepsala testovou proměnnou policy response, opravena odděleným email_accounts DTO). Další seat retry prošel předchozí gate a nyní odhalil chybějící explicitní bank selection v required_seat_checkout fixture. Fixture opravena, targeted **passed** (`sql-required-seat-policy.log`). Root spouští přesný canonical `seat-contract` step proti vlastní disposable55452 se správnými project/port env (`seat-contract-preflight.log`), aby dořešil další staré fixture assumptions v jedné dávce před dalším Terra full lane. Agent idle. Zdroj runtime je zmrazený, mohou se měnit test fixtures/evidence; tracked-wide diff digest tím není důkaz jedné source revize, finální receipt musí uvádět konkrétní validované inputs.

### Uzavřená dohledávka entrypoints -> společný owner -> executable důkaz

| Entry point / consumer | Canonical guard / owner | Důkaz |
|---|---|---|
| Public ticket/seat checkout, operator checkout, waiting offer acceptance | finalizer full org/unit resolver + shared fence, availability, ensure instructions | Global journey, required_seat_checkout, payment_operations_concurrency, connector_contract |
| `manage_form`, released `update_form_client_sync_v1`, MCP forms.save/paymentOptions | actual stored form scope, payment configuration validator, get_form_bank_accounts_internal + policy projection | MCP20 PostgreSQL, scope/template tests, setup_and_revision/projections |
| Wizard create/reset/finalize, form creation and duplicate | scoped preferred method, closed draft, same saved form validator and setup bank guard | Global MCP create/copy; setup payment_policy/adaptive_details/email_preview and copy_configuration |
| Order read/refund/record/cancel/correct and receipt retry | bulk method context, current operation support/readiness/RBAC/source, command fence before money locks | method_policy, operation_support, bank_refund, cash guards/history, refund_dispatch,14 concurrency |
| Released floating/exact cash insert and delete facade | same cash writer policy; delete delegates source-bound correction command | insert_manual transaction, cash history/configuration, operation_support legacy gateway negative |
| Pair/unpair and bank statement | actual stored order scope + bank policy; history(account,unit) requires actual link and both roles | pairing/unpaired/remove tests, tenant_scope shared A/B, ACL |
| Unit account management/linking/BankSync/user admin, direct connection route | require_bank_authoring_scope_internal, get_linkable(unit), scoped management projection, live rights listener | tenant_scope/direct picker negative, bank route39+2 revocation, server source/ACL |
| Email authoring/setup preview/template review | hierarchy + enabled linked unit; exact inherited template revision audit; preview explicit action | authoring-boundary SQL, template audit, setup preview Deno,347 editor/widget tests |
| Queue enqueue/claim/prepare/begin_send/reminder scheduler and attachments/QR | common collection_action + epoch + shared fence; exact bank source/purpose; no remote side effect | recovery_queue,14 concurrency template races,30 Edge with actual-handler matrix, ticket-edge regression gates |
| Verified ingest/reconcile and provider movements/disputes | original connector/physical account identities, existing ledgers/effects; no sales-policy filter of financial facts | Stripe totals/admission, bank excessive late event, observation-only Orchard, refund dispatch |

Nejsou zavedeny tenant-name výjimky ani druhý ledger/queue/engine. Runtime registry je jediná composition root pro konkrétní konektory. Historické adapters a jejich consumers/removal podmínky jsou výše v deletion ledgeru.

## Checkpoint 8 - plný seat-contract preflight dokončen po částech

Exact canonical `seat-contract` step byl lokálně postupně proveden v původním pořadí proti označené disposable55452. Po každém opraveném selhání se pokračovalo zbývajícími příkazy, passing prefix se zbytečně neopakoval. Logy `seat-contract-preflight.log`, `preflight2` až `preflight6`. Plná lane včetně browseru stále čeká; tyto segmenty nejsou náhradou canonical lane.

Opravy a důkazy:
- required_seat_checkout i application_only_checkout fixtures explicitně provisionují bank policy a saved selection, targeted obě prošly.
- Worker reader skutečný `SET ROLE service_role` odhalil privátní helper EXECUTE problém. `get_order_details_for_email` je nyní úzký SECURITY DEFINER s explicitním service-only EXECUTE (anon/auth revoked), bez klientského grantu k vnitřním helpers/tables; trusted contact-repair parent už předtím autorizuje. Actual worker/ACL **2 passed**, security headers/ACL **8 passed** (`sql-worker-reader.log`, `security-worker-reader.log`).
- Staré connector upgrade fixtures teď nejprve rekonstruují skutečný pre-policy stav uvnitř vlastního logical clone. Test-only lifecycle/scanner helper explicitně rozlišuje absenci nové konfigurace v tomto historickém klonu; produkční fallback nevznikl. Populated connector + additive Barion upgrade **2 passed**, `upgrade-predecessors-final.log`, peněžní a email snapshoty byte-for-byte zachovány.
- Stripe stale-recipient race narazila na předčasný obecný form readiness check. Locked connector nejprve zkontroluje originální recipient; plná konfigurace se stále ověřuje před commit/attempt/remote dispatch a chybná local preparation se rollbackuje. Released `STRIPE_RECIPIENT_CHANGED` zachován. Actual multi-connection Stripe race **1 passed**, `stripe-recipient-race2.log`.
- Barion recorded real-protocol SQL test ukázal, že public sales=closed nesmí blokovat již schválený operator sandbox intent. Registry má explicitní collectionAvailable z connector-owned gate, bank/Stripe standardně odvozují stejnou available eligibility. Barion public available zůstává false; jeho privátní gate ověřuje enabled originální connection, scope, stored binding a sandbox allowlist. Template/policy zákaz vyhrává. Recorded-protocol SQL **1 passed** s novými negativními technickými/policy assertion a observation po disable, `barion-collection-gates.log`. Žádný remote call ani skutečná platba.
- Customer overview fixture pro EUR musí převést také syntetické ledger currency facts a podporované měny účtu; původní nesoulad správně potlačil instrukce. Doplněn tento explicitní currency variant, production guard neoslaben. Overview scope/partial/full/payment matrix/ticket refresh/expiry/revocation **1 passed**, `sql-customer-overview-policy2.log`.
- Ticket Wallet assembler byl stejně jako access starý literal check přes již superseded email_queue/readiness/worker owner. Frozen wallet bytes chrání SHA256133d58b0...; nesuperseded blocks se musí shodovat, explicitní nové owners musí být effective head. Žádná instalovaná migrace se neregenerovala. Wallet/access/config/policy/ops parity prošly.
- Finální concurrency po těchto edits **14 passed**, `concurrency-authoritative.log`. Security+frozen-history source tests a MCP strict contract právě dokončovány (`security-history-authoritative.log`, `mcp-contract-authoritative.log`).

Další kroky: dokončit finální source/docs metadata a případné levné targeted checks, pak opravdu zmrazit runtime/test inputs a delegovat Terra celý závěrečný canonical batch všech8 lanes (obsahuje browser, globální Flutter slot). Root musí během toho držet source stabilní; při failure normálně opravit a opakovat affected gate. Fresh bootstrap/upgrade policy po posledních registry/reader edits a final SQL proof ještě zbývá. Goal active, žádný externí blocker, produkce nezměněna.

## Checkpoint 9 - fixed-template queue safety a scoped monotonic epoch

Při finální kontrole byl nalezen ještě skutečný leak: nový intent zařazený až po bank disable měl allowed=false, ale vlastní wrapper mohl obsahovat pevný bankovní účet. Queue nyní ověřuje kompatibilitu i těchto nových envelopů, nikoli jen původně povolené collection actions. Existující prepared obsah se nepřepisuje.

- `eshop.payment_template_epochs` je privátní konfigurační monotónní counter po occasion, aktualizovaný pod stejným org policy fence při skutečných template/wrapper writes. Hierarchie používá nejkonkrétnější scope a affected occasions; unit A edit neinvaliduje B. Není přidán finanční ledger/queue.
- Audit revision zahrnuje monotónní epoch i efektivní obsah. A-B-A změna tedy neobnoví starý review či prepared snapshot jen proto, že se HTML vrátilo ke stejné hodnotě.
- Nové order envelopes ukládají paymentTemplateEpoch; příprava/send porovnávají aktuální epoch. Legacy encrypted online/disabled-bank snapshot bez attestation není znovu odeslán; musí vzniknout nový oprávněný resend intent. Neplatební login/wallet/ticket QR algoritmy se nemění. Toto je material preflight položka pro samostatný produkční release, zde se produkční queue nemění.
- Dedupe hash porovnává původní business input; serverem odvozený collectionAction/template epoch se z hashe vyjímá pouze pro příslušné order kinds. Retry tak vrátí stejný immutable intent, jiný skutečný payload stále odmítá email_dedupe_conflict. Žádná resurrection ani opakování peněžního side effectu.
- Nový `policy_template_queue_test`: nový disabled fixed-bank intent blokován, A-B-A a následná oprava/re-enable nevzkřísí immutable snapshot, sibling B revision beze změny, stejný dedupe replay a rozdílný input odmítnut. Targeted queue/review/recovery/wallet/canonical email batch **5 passed**, `sql-template-scoped-epoch.log`.
- Předchozí canonical seat-contract preflight je nyní projitý celý po segmentech; původní failures opravitelné lokálně, finální celá lane se nesmí přeskočit. Source engine se po tomto posledním safety doplnění musí znovu ověřit fresh bootstrapem + relevantními SQL/concurrency a všemi affected canonical lanes.

Nejbližší práce: final fresh bootstrap vlastní55452, společný SQL batch včetně emails/provider/Stripe/transactions/setup/reminders; upgrade fixtures po novém epoch table; actual provider/Deno/strict MCP checks; pak source freeze a Terra celý canonical8lane batch, root bez dalšího Flutter tasku během delegace. Před tím vyřešit pouze nové skutečné failures. Goal active, produkce beze změn.

## Checkpoint 10 - finální candidate DB a upgrade evidence

- Fresh baseline+additive+contraction bootstrap **passed**, `fresh-bootstrap-final-candidate.log`.
- Společný rozsah providers/Stripe/transactions/setup/emails/reminders/deposit/customer overview/source parity: **114 passed,0 failed**, `sql-final-candidate2.log`. První batch měl111/3: doplněny explicitní policy v language/timezone a email authoring fixtures a skutečný legacy no-form order reader dostává no-collection místo výjimky. Tři targeted fixes prošly a celý batch byl pak green.
- Policy predecessor/additive+contraction, populated connector upgrade a Barion upgrade: **3 passed,0 failed**, `upgrade-final-candidate.log`. Clone rekonstrukce zahrnuje i novou privátní epoch tabulku; zdrojová DB se nedowngraduje.
- Actual production Edge presenter/handler/QR/refund sada **30 passed**, `edge-final-candidate.log`; skutečný emailRenderer a setup preview Deno check **passed**, `edge-check-candidate.log`.
- Security/frozen source tests **11 passed**, strict MCP contract **8 passed**, MCP docs aktuální. SQL114 zahrnuje aktualizované private table/ACL a template queue cases.
- Poslední UI kontrola správy účtů právě běží (`flutter-bank-management-candidate.log`, exec43014). Potom už pouze source freeze a závěrečný canonical8lane batch v Terra, root bez concurrent Flutter. Neprohlašovat7 dřívějších green lane names za finální source proof po posledních změnách queue/registry/readeru.

Stále goal active; produkce, žádné commit/push/deploy/live platby beze změn. Pro samostatný release je nutná autorizovaná inventory/preflight existujících legacy připravených e-mailů bez policy/template attestation; zde se pouze ověřilo lokální blocking a zachování auditu.


## Checkpoint 11 - source freeze a závěrečné gates

- Finální správa bankovních účtů **6 passed**, `flutter-bank-management-candidate.log`.
- Po scoped template epoch a no-form guardu skutečná PostgreSQL concurrency znovu **14 passed,0 failed**, `concurrency-final-scoped-epoch.log`.
- Konečné non-doc inputs uloženy do `.git/payment-method-policy-baseline/final-inputs.json`:9288 souborů, SHA256 `3bb0f2b14c0caf1e753c72be75bc61431b9b3c034a79417a905ca137f8dfe074`. Po canonical batch je nutné porovnat skutečné bytes. Runtime/test edits jsou pozastavené; průběžný RESULT je z manifestu vyloučen.
- Oddělitelný tracked delta proti zachovanému počátečnímu indexu: `.git/payment-method-policy-baseline/implementation-relative-to-baseline.patch` a `.stat`,193 souborů,15233 additions/1377 deletions v okamžiku freeze. Zahrnuje23 nových cest. Počáteční untracked obsah má pouze inventory, nelze automaticky přisuzovat souběžné cizí editace; originální25MB tracked patch se zachoval. Skutečný index ani HEAD se tím neměnily.
- Terra dostal všechny8 lanes v jednom canonical batch: image-contract, web-startup, wix-checkout-compatibility, navigation-interactions, server-policy, client-contract, seat-checkout, ticket-preview-and-delivery. První pokus bezpečně odmítnut: mirror lock drží jiná session. Agent čeká, nic nezabíjí a lane gates nepřeskakuje. Root nespouští Flutter ani nemění validované sources.

Goal active. Zbývá skutečný konečný canonical batch, potvrzení stabilních inputs a finální uzavření matice/deletion ledgeru. Žádný externí autorizační blocker; čekání na sdílený lokální CI slot. Produkce beze změn.


## Checkpoint 12 - canonical six green, notification fixtures doplněny

Finální batch (`ci-final-batch.log`) prošel image-contract3.4s, web-startup48.5s, wix9.5s, navigation47.9s, server8.6s, client36.9s. Seat-contract42.0s prošel celý. Seat-notifications:32 passed/2 failed kvůli implicitní historické bankovní konfiguraci ve fixturech, nikoli kvůli oslabení guardů. Ticket lane se po failure nespustila.

Opraveny pouze dva SQL testy: `notification_center/producers_test.sql` explicitně vytváří bank policy, recipient a saved selection; `form_availability_save_test.sql` explicitně volí povolenou cash policy pro default paid produkty. Jeho raw schedule edit nyní zachovává payments; skutečná failed-save assertion používá neplatný account, protože cash kontrakt deadline záměrně ignoruje. Targeted oba **passed**, `sql-notification-explicit-policy3.log`.

Runtime se nezměnil; šest předchozích green lanes zůstává relevantních. Manifest porovnání před opravami:0 differences. Nový manifest se liší přesně těmito2 SQL fixtures, SHA256 `c40ec1423517d861afc8deef3e47efebae24fe30a6a6bfc3d0f6cc5328ed9ef2`; původní bytes uchovány jako `final-inputs-before-notification.json`. Terra nyní provádí canonical `seat-checkout ticket-preview-and-delivery`, log `ci-final-remaining.log`. Root znovu drží source/test freeze, nespouští Flutter. Goal active, finální gates ještě nejsou hotové.


## Checkpoint 13 - browser fixture explicit policy

Canonical seat retry (`ci-final-remaining.log`) prošel všechny SQL prerequisites, včetně34 notification tests a celého seat-contract. Browser offline-recovery se zastavil na disabled submit, protože seat fixture neprovisionovala policy ani saved form selection; UI pravdivě ukázalo nedostupné platby. Žádný bypass tlačítka ani guardu.

`web_client/tests/fixtures/seat_checkout/setup.sql` nyní explicitně provisionuje banktrue a saved bankEnabled selection ke stávajícímu skutečně linked účtu. Jediná změna proti předchozímu manifestu je tento fixture soubor; runtime beze změny. Před změnou agent potvrdil9288/9288 identical. Nový manifest SHA256 `4fc49bfb9575db1ee22342af851d5ddc4f26285aa21534f2c49f59062d13b3b7`, předchozí uložen `final-inputs-before-seat-browser.json`. Terra opakuje celé dotčené canonical seat-checkout + ticket-preview-and-delivery (`ci-final-remaining2.log`). Šest ostatních lanes těmito výhradně seat test fixtures není změněno. Goal active do skutečného green výsledku.


## Checkpoint 14 - dokončeno, konečné podmínky splněny

**Všech pět vln a akceptační matice1-14 jsou implementované a lokálně ověřené. Žádný zbývající lokální blocker ani neúspěšný povinný gate.** Deletion ledger má u každé položky odstranění nebo výslovnou plánovanou protocol/history hranici s consumerem a podmínkou odstranění. Žádné nové paralelní finance/queue/engine, žádná tenant-name výjimka či implicitní bank fallback. UI je zapojené do skutečných tenant/unit/form a financial consumers, nikoli placeholder API.

### Konečné canonical CI

| Lane | Výsledek | Evidence |
|---|---|---|
| image-contract | PASS3.4s | `ci-final-batch.log` |
| web-startup | PASS48.5s | `ci-final-batch.log` |
| wix-checkout-compatibility | PASS9.5s | `ci-final-batch.log` |
| navigation-interactions | PASS47.9s | `ci-final-batch.log` |
| server-policy | PASS8.6s | `ci-final-batch.log` |
| client-contract | PASS36.9s | `ci-final-batch.log` |
| seat-checkout | PASS92.4s | `ci-final-remaining2.log`, `ci-final-seat-checkout-detail.log` |
| ticket-preview-and-delivery | PASS71.5s | `ci-final-remaining2.log`, `ci-final-ticket-preview-detail.log` |

Prvních6 lanes validovalo konečné runtime inputs. Poté se změnily výhradně dvě notification SQL fixtures a seat browser setup, které náležejí opakované seat lane; žádný runtime edit. Opakovaná seat lane zahrnula celý SQL/MCP/connector/concurrency prefix a browser. Ticket lane běžela celá až po těchto změnách. Browser prokázal skutečný klik mapy -> SQL rezervaci -> preview -> order -> přiřazené místo; offline release/reconnect/authoritative recovery zachoval místo a odpovědi s jedinou objednávkou. Izolovaný headless session po testu uklizen. Receipt: `browser-gates-receipt.md`.

### Další relevantní důkazy

- Fresh disposable bootstrap baseline + oba nové forwardy passed; finální canonical lanes znovu bootstrappovaly aktuální sources. Frozen historické migrations nebyly regenerovány.
- SQL114/0failed v `sql-final-candidate2.log`; policy/connector/Barion upgrade3/0failed v `upgrade-final-candidate.log`, financial facts a email snapshots zachovány. Canonical seat pak znovu vykonal relevantní provider/upgrade/contracts.
- Skutečné více-session concurrency14/0failed po scoped epoch v `concurrency-final-scoped-epoch.log`, opět obsažené v canonical seat. Policy/instruction/checkout a template/send obě pořadí bez side effectů za fence.
- Edge actual handlers/presentation/refund/QR30/0failed v `edge-final-candidate.log`; Deno production renderer/setup typecheck passed. Targeted MCP strict8, actual PostgreSQL settings20/config15 passed, navazující canonical MCP gate také passed.
- Flutter targeted model/widget/email347, form25, bank routes39+2 revokace, bank management6 passed; canonical client/navigation/ticket tests passed. Analyzer cílených14 files:0errors/0warnings,27 info lints, nejde o bezvýhradný clean lint výsledek. Source UI detector `[]`, ne pixel audit.

Finální integrita `.git/payment-method-policy-baseline/final-integrity.json`: všech9288 recorded non-doc inputs identických, **0 nezaznamenaných non-doc additions**, manifest SHA256 `4fc49bfb9575db1ee22342af851d5ddc4f26285aa21534f2c49f59062d13b3b7`. HEAD `742d614b722bbe619b3a095f66605bd4bb536006` nezměněn. Úvodní tracked snapshot i oddělený implementační patch jsou zachovány; skutečný Git index se neměnil.

### Samostatná produkční hranice

Produkce nebyla čtena ani změněna tímto úkolem; žádný commit/push/deploy, live aktivace ani skutečná platba/refund. Připravené lokální migrace nejsou tvrzením o jejich produkční aplikaci. Před samostatně autorizovaným release je nutná scoped inventory/preflight legacy připravených email snapshots bez policy/template attestation, vyhodnocení templates a případný nový oprávněný resend; současný worker je bezpečně blokuje a zachovává audit. Reálnou connector readiness/live Global konfiguraci tento lokální důkaz netvrdí. Existující pending závazky a historické ledger facts se nemažou.

Goal se uzavírá complete pouze na základě výše uvedeného dokončení, nikoli kvůli času nebo rozpočtu.


## Checkpoint 15 - následná architektonická oprava, triggery zakázány

Uživatel požaduje dořešení skutečných blockerů a architektonicky čistý výsledek; výslovně odmítá doménové triggery, výjimkou jsou pouze mechanická metadata typu last_updated. Následná kontrola našla rozpor: template epoch/fence byly zavedeny trvalým BEFORE triggerem. Předchozí prohlášení architektonického dokončení tím bylo příliš silné; šlo o chybu implementace navzdory green behavior tests.

Oprava: žádný CREATE TRIGGER, explicitní DROP obou triggerů a staré trigger funkce. Soukromý invoker `payment_template_write_scope_internal(context,invalidate)` sdílí scoped org fence a monotónní invalidaci, bez doménového triggeru. Existující hierarchy lock bere policy fence před row locks. Autorizované update/reset template a banner owners invalidují v téže transakci; moderní receipted příkazy i released RPC delegují stejným owners. Nové occasion initialization/copy nemají staré snapshots, delete_occasion odmítá všechny existující orders; non-payment access/sale/waitlist seed obsah nemění payment templates. Privileged custom-wrapper/data migration musí volat explicitní write scope ve stejné transakci. Žádná druhá business implementace.

Forward manifest zahrnuje změněné canonical authoring owners, historie zůstává frozen. Staré trigger definer ACL/header deklarace se odstraňují. Concurrency tests nyní mění wrapper přes skutečný autorizovaný banner RPC, nikoli přímý INSERT s triggerem; přidán behavior proof template RPC epoch a katalogová absence triggerů. Běží fresh disposable bootstrap55452 (`fresh-bootstrap-no-triggers.log`); poté targeted template/authoring/queue SQL, skutečné concurrency14, upgrade/parity/security a affected canonical CI. Produkce beze změn. Tato následná oprava zatím není prohlášena za ověřenou/dokončenou.


## Checkpoint 16 - explicitní authoring bez triggeru, targeted green

- Fresh baseline+forward+contraction bootstrap55452 **passed**, `fresh-bootstrap-no-triggers.log`. Následná kosmetická konsolidace autorizace banner owneru byla aplikována z canonical source v transakci; finální CI bootstrap ověří celý aktuální assembly znovu.
- Šablony/queue/recovery/email/tenant scope/setup/parity **33 passed**, `sql-no-triggers.log`; poslední explicitní DML revokes a absence triggerů + source parity **2 passed**, `sql-template-boundary-no-triggers.log`.
- Actual multi-session concurrency **14 passed**, `concurrency-no-triggers.log`. Template races už používají skutečný `update_entity_email_banner`, včetně autorizace a explicitního policy fence před hierarchy locks; obě pořadí proti send permit prokázána skutečným PostgreSQL blocking, ne sleep domněnkou.
- Upgrade policy + populated connector + Barion **3 passed**, `upgrade-no-triggers.log`. Frozen migration parity (access/wallet/payment ops/email communication/policy) a security headers/ACL tests passed, `security-no-triggers.log`, `parity-no-triggers.log`.
- Privátní write-scope helper je SECURITY INVOKER bez API EXECUTE. Přímé INSERT/UPDATE/DELETE nad oběma template tabulkami odebrány PUBLIC/anon/authenticated/service_role, zachován stávající read kontrakt. Všichni runtime callers používají existující checked RPC, žádný přímý klientský DML caller nebyl nalezen. Metadata-only triggers zůstávají: přesný katalog všech11 je `trigger-catalog-final.txt`; výhradně `moddatetime` a `update_updated_at_column`.
- Pravidlo ai_context upřesněno podle uživatele: jediná technická výjimka je last-updated metadata; žádná domain invalidation v triggeru. Architektura a autoritativní plán popisují explicitní writer hranici.

Zdroje/testy zmrazeny, nový9288-file manifest SHA256 `d739e4bf7efe5ddeb092168b680afa1c2b37ffe73d37e8b18d0ad9b59662232f`, původní uložen `final-inputs-before-no-trigger-cleanup.json`. Terra má celý8lane canonical batch, `ci-no-triggers-final.log`. Root nedělá Flutter ani source edits. Následná oprava čeká pouze konečné canonical gates + integritu; produkce beze změn.


## Checkpoint 17 - no-trigger canonical batch a ACL fixture

`ci-no-triggers-final.log`: image3.3s, web47.7s, wix9.3s, navigation49.1s, server8.8s, client39.7s **PASS**. Seat-contract odhalil pouze obsolete testovou signature odstraněné trigger funkce (`has_function_privilege` na neexistující objekt),26 ostatních SQL passed. Browser/ticket se ještě nespustily. Detailní vlastní logy archivovány v `no-triggers-detail/`; runtime inputs při běhu stabilní9288/9288.

`policy_acl_test.sql` nyní testuje EXECUTE denial nového privátního invoker helperu a explicitní absenci staré trigger funkce. Targeted **1 passed**, `sql-acl-no-triggers.log`. Změnil se pouze tento test; šest předchozích PASS zůstává platných pro konečný runtime. Aktualizovaný manifest SHA256 `54732fed12c71471d2bdb656c94d3dd95450c6c4fbc6a51c217af3e41cb6c353`. Terra opakuje canonical seat-checkout + ticket-preview-and-delivery, log `ci-no-triggers-remaining.log`. Žádná další runtime změna, root Flutter slot nepoužívá. Produkce beze změn, finální následná oprava ještě čeká tyto2 green gates.


## Checkpoint 18 - následná architektonická oprava dokončena

**Žádný lokální blocker nezůstává. Doménové policy/template triggery i původní trigger funkce odstraněny.** Jedinou povolenou výjimkou jsou mechanické last-updated metadata, jak uživatel výslovně požadoval. Přesný katalog celé disposable application DB obsahuje11 takových triggerů, žádný jiný (`trigger-catalog-final.txt`); vlastní `update_updated_at_column` pouze nastavuje `NEW.updated_at=NOW()` a vrací NEW, ostatní používají standardní moddatetime.

Canonical owner je explicitní privátní invoker `payment_template_write_scope_internal(context,invalidate)`. Stávající autorizované template/banner save/reset příkazy zajišťují fence před hierarchy locks a invalidaci v téže transakci. Stale receipted conflict ani replay neprovádí nový write. Přímé API DML nemůže tuto hranici obejít. Nové/copy occasion inicializace nemají předchozí snapshots; historické protokolové adaptéry delegují stejným owners a mají podmínku odstranění v deletion ledgeru. Žádná paralelní doménová implementace nebo náhradní trigger.

### Konečné canonical výsledky po odstranění triggeru

| Lane | Výsledek | Log |
|---|---|---|
| image-contract | PASS3.3s | `ci-no-triggers-final.log` |
| web-startup | PASS47.7s | `ci-no-triggers-final.log` |
| wix-checkout-compatibility | PASS9.3s | `ci-no-triggers-final.log` |
| navigation-interactions | PASS49.1s | `ci-no-triggers-final.log` |
| server-policy | PASS8.8s | `ci-no-triggers-final.log` |
| client-contract | PASS39.7s | `ci-no-triggers-final.log` |
| seat-checkout | PASS94.6s | `ci-no-triggers-remaining.log` |
| ticket-preview-and-delivery | PASS100.4s | `ci-no-triggers-remaining.log` |

První batch měl jediný obsolete ACL test, opraven pouze jeho signature a přidána absence smazané funkce; žádný runtime edit po prvních6 PASS. Celá seat a ticket lane pak prošly s konečným testem. Detailní logy v `no-triggers-detail/`, browser receipt v `browser-gates-receipt.md`. Browser skutečně prokázal click/reservation/order i offline recovery, task session uklizená. Targeted SQL33+2+ACL1, concurrency14 a upgrade3 prošly nad novou explicitní cestou; canonical seat zahrnul fresh aktuální migration bootstrap, parity, celé policy contracts i concurrency. Stávající klientské/Edge důkazy platí pro nezměněné zdroje a byly doplněny aktuálním canonical batch.

Finální integrita `final-integrity-no-triggers.json`:9288/9288 unchanged;0 nových aplikačních inputs. Stejný explicitní manifest scope od začátku vyjímá `docs/`, `.agents/` a symlinky; ty nejsou vydávány za ověřené runtime inputs. SHA256 manifestu `54732fed12c71471d2bdb656c94d3dd95450c6c4fbc6a51c217af3e41cb6c353`. HEAD nezměněn. Finální oddělitelný patch proti úvodnímu tracked snapshotu se aktualizoval, skutečný index se neměnil.

Předchozí tvrzení o dokončení architektury opravuje tento checkpoint: behavior green tests samy neomlouvaly zakázaný trigger. Po jeho náhradě jsou dokončené všechny původní vlny, matice a kontrakce v autorizovaném lokálním rozsahu. Produkce zůstává beze změn, bez commit/push/deploy/live plateb/refundů. Samostatně autorizovaný produkční preflight/aktivace a inventura legacy prepared emails zůstávají hranicí budoucího release, nikoli lokálním implementation blockerem.

Navazující autorizovaný refaktor všech4 odsouhlasených příležitostí je dokončen a lokálně ověřen v [samostatném realizačním záznamu](payment-policy-refactor-RESULT-2026-11-12.md), checkpoint4. Původní frozen migrace160000/170000 se nezměnily, chování doplňuje nový180000 forward. Původní checkpoints zachycují své tehdejší inputs.
