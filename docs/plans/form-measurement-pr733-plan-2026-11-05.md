# Doplnění PR #733: vypnuté měření, UI/MCP a izolované integrace

Datum: 2026-11-05
Stav: Plán doplnění PR; jádro připravené k implementaci, izolované GTM má povinný ověřovací bod.
Verification: standard (oprávnění, veřejný kontrakt, SQL a cizí JavaScript).

## Výsledek a rozsah

Pořadatel může v UI i přes MCP uložit konfiguraci měření, samostatně je zapnout/vypnout a zjistit, co jeho spuštění blokuje. Nové i existující formuláře začínají s měřením vypnutým. Samotné zadání GTM ID, skriptu ani vložení embedu nic nezapne. Vypnutí zachová konfiguraci. Kopírování měření nepřenáší.

Doplnit existující PR, zachovat jeho validní whitelisty, SQL oprávnění, aggregate save, embed protokol a datovou minimalizaci. Cizí kód nesmí běžet v dokumentu formuláře na originu aplikace. Plný výsledek zahrnuje ověřené izolované GTM; bezpečně omezené jádro lze dokončit samostatně, ale nesmí být vydáváno za dokončení celé původní funkce.

Rozšířené konverze se v tomto balíku nenabízejí jako aktivovatelná funkce. Přípravu jejich konfigurace lze zachovat, přenos kontaktů zůstane tvrdě blokovaný. Jejich pozdější aktivace vyžaduje samostatnou implementaci souhlasu, schválený účel a odpovídající informace návštěvníkům. Nevybíráme poskytovatele CMP, nekupujeme doménu, neprovádíme migraci, deploy, commit, push ani komentář do PR.

## Pevný bod a důkazy

Zdroj: https://github.com/festappnet/festapp/pull/733

- PR head: `2be3c5274197f2a11492efd70d2b4f3e89388904`.
- PR base při průzkumu: `5934dd76d815125518b8a2f06af960ddb51d8c7a`.
- Lokální `main`: `a31277e3c3d761ed37d6425a1f2a731584b92e8d`, s rozsáhlými nesouvisejícími změnami. Nesmí sloužit jako náhrada diffu PR ani být přepsán při přípravě implementace.
- Architektura konzultována s nezávislým agentem `gpt-6-astra`, reasoning `medium`, podle výslovného zadání uživatele. Toto není runtime ani bezpečnostní certifikace.

| Zjištěný fakt v PR | Místo | Důsledek |
|---|---|---|
| Chybí hlavní `enabled`; přítomné ID/kód stačí loaderu | `form_settings.sql`, `loadFormIntegrations` | Konfigurace a aktivace musí být oddělené |
| Emise nekontroluje konfiguraci měření | `FormDataLayer.enabled()` v `form_datalayer.js` | Opravit všechny události, včetně page_view a embedu |
| UI má GTM ID, kód a enhanced switch | `form_settings_content.dart` | Doplnit hlavní přepínač, stav a srozumitelné blokace |
| MCP umí tři analytics klíče přes `forms.save` | `tools/festapp/src/operations/forms.mjs` | Zachovat jednu mutaci, rozšířit vstup i čtení stavu |
| MCP návratové snapshoty používají strict Zod schéma | `formState`, `snapshot`, `formDataSchemas` | Změny projekcí musí mít shodné return schéma |
| Autoritou je organization admin, nikoli vlastník platformy | `can_manage_form_measurement`, `forms.measurement.write` | Org admin nesmí sám povolovat platformní politiku |
| Veřejný bundle přebírá effective form metadata | `get_form_bundle_internal`, `get_effective_form_data` | Uložený kód nesmí automaticky pronikat do veřejné konfigurace |
| Guard přepisuje history a poslouchá Auth | `installFormIntegrationGuard`, `navigateWithFormReturnContext` | Po odstranění same-origin loaderu odstranit i tyto zásahy |
| `purchase` se přidává jen do první odpovědi; replay ho vynechá | `create_ticket_order_command_internal` | Ztráta odpovědi ztrácí konverzi, nelze tvrdit spolehlivé doručení |
| `purchase` znamená přijatou objednávku, ne zaplacení | `form_purchase_datalayer_internal`, PR popis | Zachovat explicitní význam, neměnit platební lifecycle |
| Whitelist a kontaktní normalizace jsou ručně duplikované | `form_datalayer.js`, `public/embed.js` | Sdílet zdroj, kontrolovat příjem nezávisle |

Před editací přečíst `CLAUDE.md`, `docs/architecture/ai_context.md`, příslušné README a `CONTRIBUTING.md`. Připravit izolovaný checkout PR bez přesunu cizích lokálních změn; znovu určit aktuální main/PR SHA a při odchylce upravit tento plán. Neprovádět automatické sloučení rozpracovaného lokálního stromu.

## Cílové vlastnictví a kontrakt

### Uložené nastavení, platformní politika a aktuální stav

Zachovat `forms.data.analytics` jako jediného vlastníka konfigurace:

```json
{
  "enabled": false,
  "gtm_container": "GTM-XXXX",
  "scripts": "<script>/* spotřebitel dataLayer */</script>",
  "enhanced_conversions": false
}
```

Chybějící `analytics`, `enabled`, `null` nebo chybné runtime hodnoty nikdy neznamenají zapnuto. SQL přijímá jen skutečné boolean hodnoty. `enabled: false` zastaví celou novou měřicí vrstvu PR včetně dataLayer, embed fronty, integrací a kontaktů; nesmí vypínat nezávislé existující provozní přehledy platformy.

Patch pravidla: vynechaný klíč zachovat, `enabled: null` vrátit na false, `analytics: null` vymazat konfiguraci a vypnout. Vypnutí přes `enabled: false` kód ani ID nemaže. Starší klient zachovává existující hodnoty, jejich vynecháním nic neaktivuje. Při kopii formuláře/akce/průvodce odstranit celý analytics blok jako v PR.

Platformní povolení uložit do samostatné chráněné SQL tabulky `public.form_measurement_organization_policy`, klíč `organization`, `enabled boolean NOT NULL DEFAULT false`, revize a evidence změny (čas, operátor, důvod). Nepřítomný záznam = false. Běžné API role včetně org admina nemají přímé zápisy; nepřidávat nový obecný lidský platform-admin RBAC. Změnu provádí vlastník pouze schváleným provozním postupem přes chráněný backend přístup. UI/MCP čtou výsledek, nikoli zapisovatelný přepínač této politiky. Existující organizační JSON není alternativní autoritou.

Jediný SQL policy modul odvozuje konfigurační způsobilost ze skutečně uloženého form -> occasion -> organization. Jeho výsledky používat v editor bundle, authoring snapshotu i veřejné projekci. Souhlas a aktuální kontext prohlížeče přidává klientský měřicí modul; SQL nesmí tvrdit, že zná návštěvníkův runtime souhlas.

Do administračního form snapshotu přidat read-only `measurement_status` s typovanými poli `requested_enabled`, `organization_allowed`, `runtime_supported`, `eligible`, `blocked_reasons`, `policy_revision`. Stabilní kódy důvodů: `disabled`, `organization_not_enabled`, `runtime_unavailable`, `no_destination`. Kontakty mají samostatný stav `enhanced_conversions_unavailable`. UI lokalizuje kódy. `eligible` není důkaz, že konkrétní návštěvník udělil souhlas. Nemutovat uložené požadavky podle tohoto odvozeného stavu.

Každé čerstvé čtení statusu znovu autorizovat proti aktuálnímu uloženému resource, i po odebrání role. Receipt je neměnný historický snapshot; stav v něm označit jako historický a po save/replay jej pro aktuální UI/MCP obnovit přes autorizovaný `forms.inspect`. Nepřepisovat durable receipt živou politikou. Pole `consent_required: true` vyjadřuje požadavek, nikoli aktuální návštěvníkův souhlas.

Veřejný reader sestavuje minimalizovaný runtime kontrakt. Při vypnutí nebo zákazu nevrací skripty ani kontaktní konfiguraci. Aktivní iframe načítá pouze scoped konfiguraci konkrétní organizace a formuláře s policy revizí. Zkontrolovat všechny veřejné/personal/preview čtecí cesty, nejen `get_form_by_link`. Runtime URL spravuje platforma, nesmí být volným vstupem organizace/MCP.

### Měřicí modul a transporty

Checkout hlásí události měřicímu modulu a nepřepisuje kvůli analytice router ani Auth. Modul má malé rozhraní: zahájení pro aktuální formulář, zaznamenání schválené události a ukončení. Vnitřně vlastní policy, whitelist, omezenou frontu bez kontaktů a transport. Zachovat nejvýše dva skutečné adaptéry: hostitelský embed a izolované měřicí prostředí.

Sdílený čistý JS kontrakt pro payloady používat v aplikaci, embed build výstupu i runtime. Každý příjemce stále provádí vlastní validaci. Do `embed.js` vložit kontrakt deterministickým build krokem; žádný ručně udržovaný klon validátorů. Nový analytics event nesmí způsobit závislost obecného `EmbedBridge` na formulářovém loaderu, auth nebo UI.

Podmínka emise je součin: požadavek formuláře + povolení organizace + podporovaný transport/cíl + veřejný bezpečný kontext + souhlas pro daný účel. Embed navíc vyžaduje existující host opt-in a důvěryhodný souhlasový handshake svázaný s originem, zdrojovým oknem a instancí. Samotný HTML atribut není souhlas. Bez implementovaného adaptéru souhlasu se externí měření nespustí; nezařazovat fiktivní `consent=true`. Události vzniklé před souhlasem se po jeho udělení zpětně neposílají.

Vypnutí/revokace uzavře frontu a zničí měřicí iframe. Definovat a otestovat dobu platnosti runtime policy nejvýše 60 sekund; při vypršení bez úspěšného ověření zastavit doručování. Na návratu do popředí ověřit před další emisí. Neslibovat odvolání již odeslaných dat ani okamžité zastavení kódu v offline otevřené stránce.

### Izolované GTM a skripty

Samostatný cross-site origin bez session Festappu, preferovaně pod oddělenou registrovatelnou doménou, s izolací úložišť mezi organizacemi (například samostatné originy). Pouhá nová cesta ani společný origin pro všechny organizace nejsou izolace. Prověřit Domain cookies, CORS, opener, iframe navigaci, sandbox a CSP; neoslabit politiku hlavní aplikace.

Rodičovský dokument vytváří iframe s důvěryhodným bootstrapem a sváže kanál s konkrétním oknem/originem a instancí. Bootstrap načte scoped konfiguraci, event payloady přijímá jen přes schválený protokol. Nepředávat JWT, capability, platební data, kontakty, obecné odpovědi, skutečnou URL s query/hash ani history state. Cizí kód nikdy nedostane objekt checkoutu ani přístup k jeho DOM.

Podporované skripty jsou výslovně spotřebitelé dataLayer. Přímé čtení formuláře, změny checkoutu a odposlech fetch nejsou součástí kontraktu. Vybraná atribuce a kanonická veřejná page_location/page_referrer se explicitně promítají z whitelistu; jinak bude GTM chybně měřit URL iframe. Parametry kampaní nepřebírat neomezeně a nikdy nepromítat neveřejný vstup. U sandboxu nevolit slepě opaque origin, který může rozbít storage potřebnou tagům.

Povinný spike s testovacím GTM kontejnerem ověří page attribution, click ID, storage/cookies, embed a standalone variantu, consent a blokovaná úložiště. Výsledek určuje podporovanou matici. Pokud požadované tagy izolaci nepodporují, zaznamenat přesný blokátor a ponechat tento transport neaktivní; rozhodnutí o změně požadavků patří uživateli. Žádný fallback na skripty v hlavní aplikaci. Zakoupení domény nebo publikace runtime vyžadují samostatné zadání.

### Konverze a SQL fakta

Zachovat doložený význam PR: `purchase` = úspěšně přijatá placená objednávka, může být dosud nezaplacená. Stav úhrady není odvozován z tohoto eventu. Free registration/waitlist zachovat jako lead; úspěšné přijetí placené nabídky čekací listiny doplnit přes stejnou projekci konverze po canonical finalizeru.

SQL vlastní potvrzené položky, ceny, měnu a stabilní analytics transaction ID, které není přístupovou capability. Prověřit skutečně účtované ceny a slevové cesty; nepřidávat druhý výpočet plateb. Událost musí být bezpečně obnovitelná při opakování stejného autorizovaného commandu. Zrušit pravidlo „analytics pouze v první odpovědi“; oddělit neměnná konverzní fakta od pokusu o doručení. Nepřidávat obecné veřejné čtení objednávky podle analytics ID. Pokud je veřejný order symbol zároveň capability, exportovat místo něj samostatný neautorizující identifikátor.

Potlačit opakovaný push v životním cyklu stránky a použít stabilní transaction_id pro příjemce. Netvrdit exactly-once ani garantované doručení: prohlížeč, adblocker a příjemce mohou událost ztratit. Selhání analytics nikdy nesmí zrušit checkout nebo změnit výsledek plateb. Nezakládat nový platební engine ani obecný serverový analytics outbox v tomto plánu.

Serverovou projekci konverzních faktů podmínit enabled a platformní politikou ze skutečného uloženého formuláře, nikoli vstupním JSON klienta; samotná anonymní objednávka není povolení k měření. Souhlas zůstává podmínkou distribuce v klientovi. Také `generate_lead` pro free registraci/čekací listinu potřebuje stabilní event identitu a potlačení duplicitních callbacků/replay; dnešní purchase fence ho nepokrývá. Po vypnutí nic zpětně nerozesílat ani nepřidávat do fronty.

## UI a MCP

UI sekce „Měření“ v existujícím nastavení formuláře:

- První ovládací prvek „Povolit měření“, default false; samostatný stav „Vypnuto“, „Připraveno“ nebo konkrétní blokace. „Připraveno“ neznamená souhlas návštěvníka.
- Oprávněný správce může konfiguraci upravit i při vypnutí. GTM validace a limit kódu zůstávají serverové; kód patří do rozbalovacího „Pokročilé nastavení“, s popisem podporovaného dataLayer rozhraní.
- Organizace bez platformního povolení vidí důvod. Nesmí působit dojmem, že lokální přepínač obejde povolení. Povolit uložení požadavku `enabled=true` při platformní blokaci, ale jasně ukázat „Požadováno, blokováno platformou“; pozdější platformní povolení je pak vědomá aktivační operace.
- Uživatel bez `forms.measurement.write` vidí konfiguraci/stav jen podle současných čtecích oprávnění a nemůže je změnit. Běžné uložení jiných nastavení konfiguraci zachová. Hlídání ztráty práv, loading, chyby a neuložený draft zahrnuje i nový přepínač.
- Rozšířené konverze zobrazit jako nedostupné s důvodem, nikoli jako funkční volný switch. Při vypnutí nemazat uloženou přípravu.
- Všech šest existujících jazyků; čeština s vykáním. Stávající admin dialogy a vzhled.

MCP používá pouze existující `forms.inspect`/`forms.save`, stejné capabilities a SQL save/receipt. Přidat `settings.analytics.enabled`, jasné preserve/reset chování, read-only `measurement_status` do strict schémat, příklad konfigurace při vypnutí, aktivace i vypnutí bez smazání ID/kódu. MCP nemůže nastavovat `organization_allowed`, odvozený stav ani souhlas návštěvníka. Vrácený receipt potvrzuje uloženou konfiguraci, nikoli spuštění tagu nebo aktuální souhlas. Odvozené live statusy nejsou součástí request hashe a replay nesmí vracet starou politiku jako aktuální: při dalším `inspect` se stav vždy přepočte, případný snapshot v receipt označit jako stav v době uložení.

## Implementační vlny

### 1. Výchozí vypnutí a serverová politika

Změnit `database/functions/eshop_forms/form_settings.sql`, `update_form.sql`, `user_permissions/form_measurement.sql`, canonical schema, authorization inventory/projection a assembler migrace. Implementovat enabled/reset kontrakt a chráněnou organizační politiku. Doplnit čistou status projekci do editor/authoring/public readerů (`get_form_for_edit.sql`, `admin_form_reads.sql`, `get_form_by_link.sql` a vlastník effective metadata). Všechny mutation cesty včetně released metadata ověřují uložený scope; policy nelze změnit podvrženým JSON.

Existující konfigurace se zachová, absence enabled zůstane false, žádný backfill na true. Novou migraci sestavit z kanonických SQL zdrojů podle skutečné historie PR; neupravovat již aplikovanou migraci, pokud se mezitím aplikovala. Manifest/ACL musí odpovídat každému novému entry pointu. Bez persistentních aplikačních triggerů.

Validace: rozšířit `database/tests/eshop_forms/form_measurement_test.sql` pro defaulty, null/reset, preserve, copy, cross-org, direct-write denial a veřejnou projekci. Ověřit canonical parity a generated authorization. Výstup: uložená konfigurace sama nic nespustí a zákaz platformy není obejitelný přes UI/MCP/legacy save.

### 2. Jediný měřicí modul a podporovaný embed

Rozdělit `form_datalayer.js` na čistý kontrakt a vlastní runtime implementaci; přepojit `form_page.js`, `embed_bridge.js` a build `public/embed.js`. Zastavit všechny emise při disabled i u formuláře bez analytics. Implementovat nezávislou validaci a souhlasový handshake, bounded queue bez PII, disposal a revokaci. Načítání same-origin skriptů odstranit už v této vlně; do dokončení vlny 4 má tento transport stav `runtime_unavailable`.

Validace: doplnit stávající `form_datalayer`, `form_measurement_contract`, `form_measurement_review`, `embed` a `embed_analytics` Node testy. Ověřit žádný push/message/load při false, žádné opožděné odeslání po revoke, fake origin/source/instance a checkout při chybě analytics. Výstup: bezpečný embed funguje pouze se všemi branami, společný kontrakt nemá ruční klon.

### 3. UI a MCP se stejným stavem

Upravit `lib/components/forms/views/form_settings_content.dart`, snapshot/draft/model dle skutečných symbolů v PR, strings a překlady. Doplnit `FormMetadata`, form settings serializer a exporty portable core, pokud je používá současná save cesta. Upravit `tools/festapp/src/operations/forms.mjs`, strict return schémata, MCP reference generator a dokumentaci. Nevytvářet druhou analytickou mutaci.

Validace: cílené Flutter widget testy pro off/configure/on/off, blokaci platformou, read-only a zachování jiných změn; MCP PostgreSQL test pro stejné operace, null/preserve, cross-org denial a strict output. Výstup: UI i MCP ukládají shodný JSON a vysvětlují stejnou způsobilost, konfigurace se vypnutím neztrácí.

### 4. Izolovaný runtime a povinné ověření GTM

Nejdřív připravit lokální izolovaný prototyp a explicitní podporovanou matici dle části výše. Nepotřebuje publikaci ani placenou doménu. Pokud není dostupný testovací GTM kontejner, dokončit ostatní práci a označit tuto bránu jako neověřenou; neprezentovat plnou podporu GTM. Pro test kontejneru je potřeba výslovně určený neprodukční kontejner bez skutečných osobních dat.

Po úspěšném ověření implementovat scoped runtime, bootstrap/config endpoint, transport a deployment konfiguraci v jedné nové jasně vlastněné části repozitáře. Název umístění určit podle existujícího Worker/static release uspořádání; nepřesunovat checkout a nevytvářet přihlašování na runtime originu. Nezavádět platformní bypass pro libovolné trusted scripts.

Validace: browser contract z izolovaných originů, pokusy číst parent DOM/storage, navigovat hlavní aplikaci, připojit jinou organizaci, injektovat URL/capability, obnovit bfcache a emitovat po revoke. Reálný test GTM pro atribuci a deduplikaci. Výstup: podporované tagy fungují bez přístupu k aplikaci; jinak přesný blokátor a neaktivní transport.

### 5. Konverzní replay, waitlist a odstranění náhradních cest

Upravit `form_purchase_datalayer_internal`, `create_ticket_order_command_internal`, browser `confirmed()` a skutečnou waitlist acceptance cestu nalezenou přes canonical finalizer. Obnovitelné konverzní fakty získá pouze stávající autorizovaný command; případná změna response contractu má cílený test. Zahrnout duplicitní callback, ztrátu první odpovědi, storage denial a cenu po finalizaci. Ověřit, zda je order symbol bezpečný pro export; při capability významu zavést samostatné analytics ID.

Smazat same-origin loader, integrační guard a jeho router/Auth hooky, analytics-only změny `card_payment_controller.js`, `router_service.js` a `main.js`, které už nejsou potřebné. Přitom zachovat existující platební return context, čištění neveřejných URL a normální navigaci. Přejmenovat/odstranit testy tvrzení „jen první odpověď“ a nahradit je testy replay bezpečného kontraktu. Aktualizovat `docs/integrations/form-datalayer.md`, embed dokumentaci a CHANGELOG podle výsledné podporované matice.

Výstup: žádná cesta nevkládá kód pořadatele do hlavního dokumentu; replay nepřijde o konverzní fakta a waitlist používá společnou projekci. Případně nedokončená vlna 4 zůstává explicitním omezením celého balíku.

## Ověření a pořadí vydání

Při plánování nebyly spuštěny testy. Tvrzení o průchodu testů v PR jsou informace autora, nikoli naše ověření. Implementace používá pnpm 11.24.0 a repo příkazy; nové závislosti jen s frozen lockfile workflow. Konkrétní cílené příkazy:

- `pnpm --dir web_client exec node --test tests/forms/form_datalayer.test.js tests/forms/form_measurement_contract.test.js tests/forms/form_measurement_review.test.js tests/core/embed.test.js tests/core/embed_analytics.test.js`.
- Repo SQL runner: `node web_client/scripts/run_db_tests.js database/tests/eshop_forms/form_measurement_test.sql`; pouze proti disposable local backendu, ověřit nastavení před spuštěním. Přidat cílené purchase/waitlist a canonical parity SQL testy.
- `python3 automation/assemble-form-measurement-migration.py --check` a existující generator check režimy pro limits/authorization po ověření jejich CLI v checkoutu PR.
- MCP: použít `pnpm --dir tools/festapp run test` se sériovým DB během podle package scriptu; může vyžadovat připravený lokální backend. Pro výběr cílených testů zachovat `test/prepare-current-sql.mjs` před Node runnerem.
- Flutter: před spuštěním ověřit volný jediný workstation Flutter slot. `fvm dart analyze` jen změněné soubory, cílený `fvm flutter test --concurrency=1` pro settings/model testy. Nepouštět souběžně s jinou Flutter úlohou.
- Browser: repository deterministic security/form-access gates pro nové public hranice a cílené UI ověření. Interakci delegovat `gpt-6.1-terra`, izolovaná background session, mute, disposable data. Žádná navigace uživatelova okna. GTM/CDN blokace nesmí rozbít objednávku.

Nepouštět celou SQL/Flutter sadu při psaní plánu. Při implementaci porovnat relevantní známé chyby s aktuálním čistým základem, nikoli s historickým popisem PR. Netvrdit nový problém za existující bez důkazu.

Budoucí vydání: nejdřív DB/politika s false a nové projekce, pak podporovaný runtime a klienti. Pro konkrétní organizaci povolit až po prokázání kompatibility nasazené verze. Platformní povolení může aktivovat již uložené enabled=true požadavky: provozní krok musí předem ukázat přesný seznam dotčených formulářů a vyžadovat schválení tohoto rozsahu. Uvolnění jedné organizace nepovoluje jiné tenanty.

Rollback: nejprve vypnout organizační policy, zastavit runtime a distribuci událostí. Zachovat konfiguraci a schema pro bezpečné čtení; nevracet klienty se same-origin loaderem. Přístup k backendu při případné později autorizované migraci přes `festapp-backend-access`; rutinní release podle pravidel delegovat levnějšímu agentovi. Tato plánovací úloha produkční zásah neautorizuje.

## Odstraňovací seznam a dokončení

| Artefakt | Konečný stav / důkaz |
|---|---|
| `loadFormIntegrations`, `installFormIntegrationGuard`, `integrationDocuments` | Same-origin implementace a její callers odstraněny; žádné vkládání tenant script do parent |
| Analytics history/Auth hooky a `navigateWithFormReturnContext` | Odstraněny; původní platební return flow projde testem |
| Ruční whitelist/normalization v `public/embed.js` | Deterministický výstup ze společného kontraktu |
| First-response-only projection a její testy | Replay-safe autorizovaná fakta, stabilní transaction ID a odpovídající testy |
| Aktivní enhanced switch a raw user_data export | V tomto balíku nedostupné v UI/MCP/runtime; uložená příprava se sama neaktivuje |
| Automatické spuštění podle přítomnosti ID/kódu | Nenalezitelné v runtime; enabled false testováno na všech surface |

Hotovo znamená: default off end-to-end; UI/MCP parity; neobejitelná organizační policy; společný whitelist; funkční souhlasová brána; replay a waitlist; odstraněné same-origin cesty; aktuální dokumentace a cílené kontroly. Plná podpora GTM navíc vyžaduje úspěšnou vlnu 4. Implementace bezpečného jádra a neověřené GTM se vykazují odděleně.

## Rozhodnutí, předpoklady a zbytková rizika

- Rozhodnutí plánu: konfiguraci lze upravit vypnutou; všechny nové analytics default false; politika vlastníka je oddělená od org admina; žádný cizí kód na originu aplikace; kontakty neaktivovat.
- Předpoklad: požadované skripty mohou být omezeny na dataLayer spotřebitele. Dopad při neplatnosti: nelze slíbit jejich kompatibilitu v izolaci; řeší se ve vlně 4 s uživatelem, nikoli bezpečnostním fallbackem.
- Předpoklad: první verze nepotřebuje změnit význam purchase na zaplaceno. Dokumentace PR tento význam výslovně definuje. Pokud produkt požaduje uhrazené tržby, přeplánovat přes existující platební transition owner, ne přes klientské potvrzení.
- Blokátory plné aktivace: dostupnost testovacího GTM kontejneru, ověřený runtime origin a konkrétní souhlasový adaptér. Nejsou překážkou implementace vypnutého jádra/UI/MCP. Nákup, produkční konfigurace a publikace mají samostatnou autoritu.
- Izolace neodvolá odeslaná data a nezaručí marketingovou atribuci při omezeních browseru. Výsledek reálného testu musí být součástí podporované matice.

Technický podklad: [same-origin policy](https://developer.mozilla.org/en-US/docs/Web/Security/Defenses/Same-origin_policy), [iframe sandbox](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/iframe), [GA4 transaction deduplication](https://support.google.com/analytics/answer/12313109?hl=en). Konkrétní kompatibilita GTM není z těchto obecných pravidel odvozena jako hotový fakt.
