# Zákaznická samoobsluha - dokončená lokální implementace

Etapy 1-5 [autoritativního plánu](customer-self-service-plan-2026-11-15.md)
jsou implementované v `/Users/miakh/source/festapp`. Režim ověřování `standard`.
Bez commitu, push, produkční migrace, release a aktivace. Souběžné změny slevových
kódů byly zachovány; tento výsledek není dokončením jejich samostatného zadání.

## Chování

Stávající e-mailové tlačítko a jeho URL vedou do rozšířeného přehledu objednávky
ve webu i Flutteru. Sdílený presenter přidává popis dostupných změn do automatických
zpráv, ručního resend a náhledů. Nevznikl druhý zákaznický portál.

Feature `customer_self_service` je výchozím stavem vypnutá. Po zapnutí pořadatel
v běžném nastavení formuláře samostatně povoluje operace, lhůty, konkrétní pole,
režim storna, povinný důvod a způsob refundace. Zapnutí automatické refundace
vyžaduje finanční oprávnění. Změny nastavení ukládá původní receipted form save.

Čtecí token nezískává write práva. Konkrétní návrh se ověřuje na uloženém e-mailu
objednávky, platí 10 minut a vyžaduje serverový náhled a výslovné potvrzení.
Otevření odkazu nic nemění. Fragment se odstraní před ostatními skripty; write
credential je pouze v paměti. Server kontroluje parent, scope, epoch feature,
revizi policy, návrh, lifecycle a současná fakta i při replay. Klienti mají
20sekundový síťový limit; nejisté potvrzení opakují se stejným UUID a bytes.

Storno může být automatické nebo vyžadovat pořadatelovo schválení; důvod je
nezávisle povinný/volitelný a nejvýše 2000 znaků. Žádost sama nemění vstup,
kapacitu ani peníze. Obsluha vidí důvod a odpověď v původním detailu objednávky,
může schválit, zamítnout nebo doloženě uzavřít ruční vyřízení. Zákazník může
stáhnout otevřenou žádost. Přijaté závazky a zpracování refundací přežijí vypnutí.

## Automatické a ruční hranice

- Automaticky: explicitně povolená bezpečná necenová pole; způsobilé storno;
  podporovaná plná online refundace přes původní zdroj a existující engine;
  celý přesun v rámci stejné akce se stejnou čistou cenou a měnou, kompatibilní
  platbou, kapacitou, skutečným začátkem i koncem termínu a explicitním mapováním produktů/odpovědí.
- Ručně: přesun mezi akcemi, cenový/měnový rozdíl, místenky, inventářové produkty,
  slevový snapshot, záloha, jiný účet/provider, chybějící povinné odpovědi,
  nejisté finance, použité/tištěné vstupenky a opravy faktury. Server vrátí
  náhled žádosti a uloží viditelný požadavek; nepřesune ani nepotvrdí falešnou změnu.
- Čekající a složené waitlist rodiny používají stávající waitlist/obsluhu.
  Samoobsluha nepřeskakuje pořadí ani neobchází nabídky čekací listiny.
- Refund intent/pending a skutečně vrácené peníze zůstávají oddělené. Není druhý
  ledger, druhá fronta ani service-role náhrada zákaznického nároku. Podporovaný
  přesun zachovává order/ticket/payment identity, přegeneruje QR a PDF/Wallet;
  starý QR se ověřeně neověří ve stávajícím skeneru.

## Ověření

Všechny databázové zápisy proběhly pouze v označených disposable lokálních DB.
Připravená migrace prošla přehráním kanonického baseline/forward pořadí. Žádný
externí e-mail ani skutečná provider refundace nebyly odeslány.

| Oblast | Výsledek a rozsah |
|---|---|
| SQL | 13 různých souborů: 5 `customer_order_changes`, overview, detail responses, refund financial projections, payment operations, Stripe admission, Wallet, Wallet producers, canonical source parity. Finální změněná autorizace znovu prošla. |
| Souběhy | 6 skutečných PostgreSQL závodů s doloženou lock bariérou: dva různé commandy na capability, současný přesný retry, stažení/schválení, policy/potvrzení, dva přesuny na poslední místo, skener/storno. |
| Web | 44 testů: ověření/potvrzení, povinný důvod, žádost bez falešného úspěchu, double click, přesný retry, 409 a nový náhled, paměťový token, názvy/datace a produkty přesunu, regrese přehledu. |
| Edge/e-mail | 10 testů; frozen Deno lock a typecheck produkčního endpointu/rendereru. Skutečně zašifrovaný source a ověřovací e-mail, striktní body parser, anonymní challenge a mapování chyb, jedno původní tlačítko a doprovodný text. |
| Flutter/core | 4 skutečně sesbírané widget testy v původní session i `ticket_default_cases.dart`; 1 core URI test. Explicitní potvrzení, přesný retry, ignorování starého async výsledku při změně scope a produkty před potvrzením. Nové klientské soubory bez analyzer diagnostik. |
| Bezpečnost/CI | 8 server security migration testů, 18 CI contract testů, assembler a source parity `--check`, `git diff --check`. Nové testy jsou zařazené do kanonických CI vstupů. |
| Nápověda | 7 CZ/EN help/search testů; katalogy, navigace, kontextové odkazy, aktuální light screenshoty a scénář s hashes. E-mailové náhledy čerstvé, 332 scénářů. |
| Skutečný prohlížeč | CS/EN: skutečný uložený e-mail -> produkční Edge -> PostgREST -> SQL -> náhled -> jedna čekající žádost, objednávka stále platná. Povinný důvod a zákaz dvojkliku ověřeny. Přesunový náhled navíc ukázal různé názvy stejně datovaných cílů a cílové produkty. Desktop 1280x1000 a mobil 390x844, light, bez vodorovného přetékání. |
| Nezávislá revize | Obě materiální UX připomínky opraveny a znovu ověřeny. Finální verdikt `ship` pro posuzovaný webový rozsah. Nativní vizuál není tímto verdiktem ověřen. |

Opakovatelné příkazy (z kořene, core test z package adresáře):

```sh
node web_client/scripts/run_db_tests.js database/tests/customer_order_changes
pnpm --dir web_client exec node --test tests/database/customer_order_changes_concurrency.test.js
pnpm --dir web_client exec node --test tests/forms/customer_order_changes.test.js tests/forms/order_overview.test.js tests/forms/order_details.test.js
deno test --frozen --lock=supabase/functions/deno.lock --allow-env --allow-read supabase/functions/_shared/customerOrderChanges_test.ts supabase/functions/_shared/orderEmailOverview_test.ts
pnpm --dir web_client exec node --test ../automation/tests/server_security_migrations.test.mjs ../automation/tests/help_pages.test.mjs ../automation/tests/help_search.test.mjs
fvm flutter test --concurrency=1 test/sessions/ticket_default_cases.dart --plain-name customer_order_overview
python3 automation/assemble-customer-order-changes-migration.py --check
python3 automation/generate_canonical_source_contract.py --check
deno run --allow-read automation/generate_email_preview_examples.ts --check
```

Dřívější selhání byla dořešena: historický overview kontrakt nově kontroluje
zakázané údaje a disabled akce; Wallet refresh respektuje explicitní expiry;
scanner race fixture používá správný actor, společnou form bariéru a JSON wire
formát. Širší existující FormPage/settings analyzer má starší `must_be_immutable`
warning a stylistické infos; celorepozitářový čistý analyzer ani release gates
nejsou tvrzeny. Provedený browser test neměří nativní vzhled nebo reálné SMTP.

## Dosud neprovedené provozní kroky

1. Autorizovat publikaci a konkrétní rollout; ověřit přesný canonical backend,
   zálohu, úplné dotčené CI/release gates a vybraného tenanta.
2. Aplikovat aditivní migraci, nasadit odpovídající Edge/shared email a worker
   dependencies, pak klienty a nápovědu. Aktuální migrační forward zahrnuje
   společné source owners; nemíchat starý klientský/backendový kontrakt.
3. Funkci ponechat vypnutou do výslovné autorizace. Pořadatel teprve nastaví
   konkrétní operace, skutečné termíny a pravidla. Migrace nic neaktivuje.
4. Při rollbacku vypnout nové akce/capabilities; zachovat audit, žádosti,
   finanční fakta, přijaté závazky a refund recovery. Neoživovat stornované QR.

Lokální prohlížeče, Edge/PostgREST preview procesy a jejich leases byly uzavřeny.
Produkční data, služby a aktivace se neměnily.
