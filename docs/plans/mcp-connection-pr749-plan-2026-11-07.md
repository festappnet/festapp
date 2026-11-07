# Dokončení PR #749: bezpečný životní cyklus MCP připojení

Datum: 2026-11-07  
Stav: Připraveno k realizaci; závěrečná kontrola Astra Medium zapracována  
Ověření implementace: `standard` - autentizace, autorizace a souběh.

## Výsledek a rozsah

Dokončit stávající [PR #749](https://github.com/festappnet/festapp/pull/749): uživatel při OAuth souhlasu zvolí nahrazení konkrétního připojení nebo nové pojmenované připojení a dobu souhlasu. Nahrazení je účinné pouze při úspěšném dokončení výměny autorizačního kódu. Opuštěný souhlas neruší původní připojení a nevstupuje do seznamu aktivních připojení. Dvě konkurenční náhrady téhož cíle nemohou obě uspět.

Tento dokument a navázaný execution prompt autorizují přípravu a místní implementaci při jejich následném zadání. Jejich vytvoření není implementace ani povolení k publikaci, merge nebo produkčnímu zásahu. Produkční vydání je samostatný krok s přesným zdrojovým SHA a vybraným tenantem. Nerozšiřovat práci na ostatní `prod/*` větve.

Zahrnout issuer, šifrované SQLite úložiště, oba souhlasové vstupy (tenant bridge a standalone), správu připojení, sdílený kontrakt, reference a regresní ověření. Zachovat existující SQL autorizační predikáty a aktuální oprávnění. Nepřepisovat OAuth provider, nezavádět obecný workflow engine, distribuované fronty nebo nový Postgres model připojení.

## Pevné body a důkazy

- Zkoumaný PR head: `0aa0654b0069ee2773bf00f880c5d026fd566187`, větev `feature/mcp-connection-choice`.
- Zkoumaný main: `7e9a8ec6c21fa0a56dc985bb65479fd3acebe320`, obsahuje dokončené PR #750. Při realizaci znovu fetch a zkontrolovat intervenující změny.
- `git merge-tree` ukázal jediný konflikt v generovaném `automation/release/help/mcp-reference.json`. To není důkaz bezkonfliktnosti budoucího main.
- Předchozí kontrola spustila `connection-choice.test.mjs`, `remote.test.mjs`, `forms.test.mjs`: 81/81 prošlo, žádný skip. Zelené testy nepokrývaly níže reprodukované chyby. Nejde o browser ani produkční důkaz.
- Nezávislý architektonický průchod: Astra Medium, výsledek changes required. Zachovat a opravit tentýž PR.
- Druhý průchod Astry ověřil skutečnou SDK hranici synchronního eventu/error handleru a následně přečetl tento plán. Zapracovány připomínky k nezávislé retenci tokenových řádků, historickým kandidátům a oddělení lifecycle od živých SQL oprávnění. Nové cílové invariants zatím nebyly implementovány ani otestovány.

| Fakt | Zdroj | Důsledek |
|---|---|---|
| `completeConsent` uloží Delegation ještě před token exchange | `tools/festapp/src/remote/server.mjs` | Uložený souhlas není důkaz vydání tokenů. |
| `activeConnections` filtruje pouze revoked/expiry a řadí od nejnovějšího | `tools/festapp/src/remote/connection-choice.mjs` | Nedokončený souhlas se stává výchozím cílem náhrady. |
| `clientConnectedAt` vzniká až při prvním přijatém resource požadavku | `server.mjs`, status tenant bridge | Nesmí se přejmenovat na důkaz token issuance. |
| `installConnectionReplacement` běží při `grant.success`, znovu nekontroluje aktivitu cíle a chybu polkne | `connection-choice.mjs` | Dva nástupci uspějí; chyba revokace vrací úspěch. |
| `storage.revoke` provádí několik samostatných zápisů | `tools/festapp/src/remote/storage.mjs` | Backend, tombstone a provider tokeny se mohou rozejít. |
| `/token` již používá omezenou frontu; SQLite volume má jediného vlastníka procesu | `server.mjs`, `storage.mjs` | Zachovat hranici jediného procesu, nezavádět replikační protokol. |
| Provider je připnut na `oidc-provider` 9.12.2 | `tools/festapp/package.json` a nainstalovaný balíček | Ověřit chování na této verzi, neopírat změnu o soukromý import. |
| Nativní token handler emituje `grant.success` po dokončení handleru; error handler přepisuje response při vyhozené chybě | závislost: `lib/actions/token.js`, `lib/shared/error_handler.js` | Synchronní transakční commit lze ohraničit před úspěšnou HTTP odpovědí; musí to doložit skutečný HTTP test. |
| AccessToken může být uložen před voláním `issueRefreshToken` | závislost: `lib/helpers/grant_common.js` | Tento hook není záruka „před mintem“. Autoritou je aktivace Delegation, nikoli existence tokenového řádku. |

Reprodukce se skutečným lokálním šifrovaným SQLite a veřejnými choice/listener funkcemi: A je aktivní, souhlas B->A se nedokončí, další výchozí C vybere B a ponechá A aktivní. Druhá reprodukce: Y->X a Z->X dokončí výměnu a oba nástupci zůstanou aktivní. Dosavadní test cleanup failure výslovně očekává HTTP 200 a aktivní staré připojení. Nahradit toto očekávání požadovanou atomickou sémantikou.

## Good practice a rozhodnutí o platnosti

Norma nepředepisuje jednotných 7, 90 ani 365 dní. [MCP authorization](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization) požaduje OAuth bezpečnost, vazbu na resource a doporučuje krátké access tokeny. [RFC 9700 §4.14](https://www.rfc-editor.org/rfc/rfc9700.html#section-4.14) vyžaduje ochranu refresh tokenů veřejných klientů rotací nebo sender constraint, rozpoznání replay a doporučuje expiraci při neaktivitě podle rizika. Konkrétní hodnoty zůstávají rozhodnutím poskytovatele.

Srovnání není přenos cizích TTL do našeho produktu: [GitHub Apps](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/refreshing-user-access-tokens) dokumentují access token 8 hodin a refresh token 6 měsíců; [Linear OAuth](https://linear.app/developers/oauth-2-0-authentication) dokumentuje access token 24 hodin; [Greenhouse MCP](https://support.greenhouse.io/hc/en-us/articles/57182931313819-Greenhouse-MCP-security-FAQ) výslovně používá krátké access tokeny a rotované refresh tokeny. Platnost refresh tokenu není automaticky absolutní délka uživatelského souhlasu a obecné OAuth dokumenty GitHubu/Linearu nejsou měření jejich MCP connectoru.

Zvolená politika pro Festapp, nikoli tvrzený průmyslový číselný standard:

1. Access token ponechat 300 sekund; autorizace nadále kontroluje živou Delegation a živá práva při každém použití. Revokace tedy nečeká na 5 minut.
2. Zachovat nabídku 7/30/90/365 dní, výchozí 7 dní. Delší období vyžaduje viditelnou explicitní volbu také u zápisových scopes. Samotný read-only přístup může zpřístupnit osobní údaje; nevytvářet falešnou hranici „rok je bezpečný pro čtení, zakázaný pro zápis“.
3. Každé připojení má pevné `expiresAt` od udělení souhlasu. Nahrazení je nový souhlas a znovu nabídne 7 dní, nepřebírá skrytě starou roční volbu. Refresh nikdy neposune absolutní konec.
4. Nová připojení mají navíc maximálně 30 dní neaktivity refresh tokenu. Nativní RefreshToken TTL je minimum 30 dní a zbývajícího absolutního souhlasu; úspěšná rotace obnoví pouze toto okno. `lastTokenExchangeAt` se inicializuje úspěšnou první výměnou a aktualizuje pouze úspěšným refresh grantem, aby společný predicate a management odvozovaly tentýž efektivní konec. Čtení statusu, managementu, neplatný refresh ani opakování použitého tokenu neprodlužují okno. Efektivní konec je minimum absolutního a neaktivního limitu. Žádný scheduler. Toto je nová explicitní produktová politika; přidat vysvětlení do obou consent UI a dokumentace.
5. Zachovat providerem prováděnou rotaci; doložit, že replay starého refresh tokenu odvolá použitelnou rodinu a související Delegation. Nepřidávat vlastní paralelní token registry nebo toleranční okno bez nové doložené potřeby.
6. Server/client/profile/resource/scope binding a živá práva se ověřují nezávisle na zvolené délce. Delší souhlas nezvyšuje oprávnění a neobchází opětovné přihlášení/MFA backendu.
7. UI uvádí maximální platnost souhlasu, datum konce a limit neaktivity. Negarantuje nepřerušený roční provoz: samostatná GoTrue session může skončit dříve. Název připojení je uživatelský štítek, nikoli ověřená hardwarová identita.

## Cílový vlastník a lifecycle

`connection-choice.mjs` vlastní validaci choice a policy kandidátů. `storage.mjs` vlastní atomickou perzistenci, aktivaci a revokaci. `server.mjs` je úzký adaptér veřejných hooků/events OAuth provideru. `delegation.mjs` vlastní použití aktivního připojení a aktuální doménovou autorizaci. Tenant bridge a standalone pouze přenášejí tentýž kontrakt a zobrazují tentýž výsledek.

Použít jeden životní cyklus nových Delegation: `pending` -> `issued`, vedle stávajícího `revoked` a pevného deadline. Pro jednorázově převzaté záznamy existuje explicitní historický stav `legacy`, který žádný nový consent nevytváří. `issuedAt` označuje dokončenou serverovou výměnu, `clientConnectedAt` první skutečné použití. Nezavádět další duplicitní „active“ boolean. Aktivita se odvozuje z issuance, revokace a deadline, s níže popsanou výjimkou dostupnosti legacy. Přesné názvy polí nejsou veřejný API závazek.

### Consent a pending

- `completeConsent` vytvoří pending Delegation, volitelný přesný `replaces` a backend binding. Stanovit pevné `pendingExpiresAt` jako minimum absolutního konce původní interaction a `expiresAt`. Původní interaction platí 600 sekund; consent, nový backend write, vydání kódu ani aktivita tento pending termín neposunou. Nativní autorizační kód nadále platí 60 sekund a kontroluje se samostatně.
- Pending není kandidát náhrady ani aktivní položka managementu a jeho tokeny nemohou číst ani zapisovat. Status rozlišuje čekání na dokončení od aktivního připojení.
- Do první výměny potřebuje provider legitimní přístup k pending metadatům. Použít explicitní issuance větev, nikoli obecně povolit pending v resource/refresh autorizaci.
- Při aktivaci povýšit TTL Delegation, Binding a Backend pouze do původního `expiresAt`. Backend refresh write nesmí sám prodloužit pending na roční TTL.

### Token exchange a atomická náhrada

- Zachovat existující `/token` frontu a process lock. Validovat klienta, PKCE a nativní kód providerem; nepřepisovat vlastní `/token` implementaci.
- Přes veřejný hook lze včas odmítnout zastaralý target. Nesmí se tvrdit, že `issueRefreshToken` běží před vytvořením AccessToken. Rozhodující kontrola je v atomické aktivaci.
- Synchronní handler `grant.success` pro `authorization_code` zavolá pro každé nové připojení, včetně mode new, jedinou synchronní storage operaci `activateConnection(grantId)` (nebo stejně úzký ekvivalent). Žádné neawaitované async listenery. Initial code issuance musí pending připustit i v TTL callbacku RefreshToken; běžný refresh jej musí odmítnout.
- Jedna SQLite transakce znovu ověří pending nástupce, jeho deadline, přesnou shodu actor/client/profile, aktivní vydaný target (nebo výslovně zvolený legacy target podle níže uvedené výjimky) a poté povýší novou Delegation/TTL a odvolá starou: backend, revoked tombstone a provider records podle `grant_id`. Revokace i při ručním odvolání, replay a auth failure používá tentýž interní primitiv. Transakci vlastní vnější operace; nevytvářet vnořený BEGIN ani kopii revokační logiky.
- První úspěšná aktivace vyhrává. Další souhlas proti témuž již odvolanému cíli končí `invalid_grant` a vyžaduje nový souhlas; nesmí tiše vytvořit další nezávislé připojení. Smazaný/ručně odvolaný/expirovaný target má stejný výsledek.
- Chybu commit nepohlcovat: rollback ponechá target aktivní a nástupce pending, nepoužitelného. Provider musí vrátit OAuth error bez tokenových polí: zastaralý target `invalid_grant`, infrastrukturní chyba `server_error`. Částečně vytvořené provider tokeny nejsou důkaz úspěchu a nedostanou oprávnění; pending metadata a session vyprší v pending deadline. Tokenové řádky mohou zůstat do nativní TTL a nesmějí se nikde použít jako aktivace. Odstranit je při známém rollbacku bezpečnou cleanup operací, pokud úložiště funguje; bezpečnost nesmí záviset na úspěchu cleanup. Pro fault injection použít skutečné SQLite a chybu mezi jednotlivými mutacemi. Spotřebovaný code po rollbacku nelze transparentně zopakovat - je nutný nový login/consent.
- Po commit je lokálně právě jeden aktivní nástupce. Pád před commit vrátí původní stav; pád po commit a před doručením HTTP odpovědi může vyžadovat nové přihlášení. Nelze atomicky garantovat doručení přes síť a SQLite commit. Audit nesmí tvrdit „klient obdržel token“.
- Nezavádět retry worker pro odvolání opuštěných pending souhlasů. S atomickým commit není separátní cleanup side effect, který by potřeboval durable frontu.
- Audit po commit používá pouze hash identifikátorů nového/starého připojení, typ události a bezpečný error code. Chyba audit sinku nesmí změnit úspěšný commit na neúspěšný OAuth response. Bez tokenů, session, syrových ID a názvů v logu.

### Obnova a existující úložiště

Zachovat šifrovací klíč, process lock a volume, nic nerotovat. SQLite změny provádět v jeho vlastníkovi, ne Postgres migrací. Nový issuance marker musí vznikat při každém novém consentu, nesmí být dlouhodobou volitelnou fallback větví.

Při startup upgrade jednorázově a transakčně normalizovat staré Delegation z main, které marker nemají. Zachovat jejich současná oprávnění, pevný konec a možnost použití; neodvozovat nové roční oprávnění. Pro historické záznamy není spolehlivý důkaz samotného issuance: tokenové řádky ani absence `clientConnectedAt` nestačí k jistému závěru o doručení. Označit je explicitně jako historicky převzaté, nikoli nově pending. Neznámé historické připojení bez prokázaného použití automaticky nepředvybírat k náhradě; uživatel je může zvolit výslovně. Nová připojení už toto pravidlo nemají.

Jednotný candidate predicate proto připouští aktivní `issued` a aktivní historické `legacy`, vždy se stejným vlastníkem/klientem/profilem. Legacy bez `clientConnectedAt` má `defaultEligible: false` (nebo ekvivalentní metadata), nikoli automatický první výběr podle pořadí. UI vybírá pouze způsobilý default a při jeho absenci vyžádá explicitní volbu cíle nebo nového připojení. Stejnou explicitní legacy způsobilost ověří transakce aktivace. Legacy je datová kompatibilita omezená původním deadline, ne další OAuth flow.

Limit neaktivity se zavádí pro nové souhlasy. Existujícím připojením nevymyslet neznámé datum posledního refresh, nezkrátit je potichu. Tuto historickou výjimku uložit normalizací dat, ne větvením podle chybějících polí ve všech čtenářích. Dočasná upgrade větev má version metadata, idempotentní opakování a test restartu. Převzaté záznamy přirozeně zaniknou v původním deadline; nezavádět trvalý endpoint, flag nebo V1/V2 cestu.

Před implementací zjistit, zda někde bylo nasazeno nekanonické PR #749. Pokud ano, zachovat i jeho absolutní limity, ale nerozpoznané pending bez důkazu nepřevádět automaticky na roční vydané granty. Zapsat konkrétní bezpečnou migraci podle nalezených záznamů; neprohlížet produkční volume bez příslušné autorizace. Tato informace není blokátorem lokální implementace, je podmínkou vydání.

## Implementační vlny

### 1. Aktualizace PR a regresní kontrakt

V izolovaném worktree založeném na PR zachovat cizí checkouty. Fetch aktuální main a PR, prohlédnout intervenující commity, aktualizovat stejný PR podle repo politiky. Konfliktní `mcp-reference.json` regenerovat pomocí `pnpm --dir tools/festapp run docs:generate`; zachovat popisy measurement z PR #750 a aktuální cash RPC. Žádné ruční slučování zdrojových digestů.

Přidat skutečné HTTP/OIDC + SQLite regresní scénáře do `tools/festapp/test/remote.test.mjs` a čisté choice scénáře do `connection-choice.test.mjs`. Nejdříve dokázat selhání požadovaných scénářů na původním PR. Nahradit test, který schvaluje HTTP 200 při cleanup failure.

Výstup: aktuální base a reprodukovatelné regrese. Kontrola: cílený Node test příkaz z části ověření; neplést záměrně červenou regresi s předchozími 81 passing testy.

### 2. Jedna transakční aktivace a revokace

Změnit `storage.mjs`, `connection-choice.mjs`, `server.mjs`, `delegation.mjs`, `tenant-bridge.mjs`, `management.mjs`: normalizace dat, pending/issued, atomická revokace, promotion TTL a jednotný active predicate. Upravit backendStore write pro pending. Odstranit dosavadní best-effort listener a nekonzistentní odvozování aktivity. Native provider adaptéry nadále používají tentýž storage owner.

Pro synchronní event error doložit přes reálný `/token`, že provider vrátí chybu bez připravených tokenových polí. Pokud fakt na aktualizované závislosti neplatí, upravit tento plán před pokračováním a použít veřejný middleware/hook před response. Nezavádět soukromé SDK importy ani vlastní fork provideru.

Výstup: všechny souběhové a rollback scénáře prochází, cizí target nejde odvolat, restart neaktivuje pending. Kontrola: targeted remote/choice testy v jednom procesu; fault test kontroluje stav backendu, Delegation i provider records po znovuotevření storage.

### 3. Platnost, refresh a obě UI

`packages/festapp_contracts/mcp-connection.mjs` vlastní společné konstanty (včetně zvolené neaktivity), bez jejich kopií v UI. `server.mjs` vlastní TTL adaptér a aktualizaci úspěšného exchange; ostatní runtime čtenáři používají jednotný deadline/active predicate. Rotaci a replay ověřit na reálných nativních RefreshToken objektech. Refresh neaktivního/expired/revoked/pending připojení odmítnout i při existenci provider tokenového řádku.

Upravit `web_client/src/components/mcp/mcp_connection_page.js`, `web_client/src/components/users/account_connections_page.js`, dále `tools/festapp/src/remote/views.mjs`, jejich testy a `supabase/functions/mcp-session-exchange/handler_test.ts`. Zachovat oba vstupy, libovolného registrovaného klienta včetně Make a současné výběry scopes. Název trim, max 80 znaků a zákaz řídicích znaků zůstávají; při náhradě jej lze zdědit. Chybějící choice u starého externího požadavku zachová nezávislý nový 7denní souhlas, nesmí potichu odvolávat připojení.

UI formálně česky; aktivní/nepoužité/čekající stavy nezaměnit. Nabídka replacement obsahuje pouze vydané aktivní připojení stejného user/client/profile a explicitně způsobilé historické kandidáty podle kompatibility výše. Historicky neprokázaný kandidát se nevolí automaticky. Žádný nový rozpracovaný souhlas se nesmí stát kandidátem ani výchozím.

Výstup: jednotná policy v tenant i standalone, přesný konec, správné výchozí volby a pravdivý status. Kontrola: Node remote, web component a Deno handler testy; lokální skutečný browser průchod níže.

### 4. Kontrakce, dokumentace a trvalá CI ochrana

Odstranit položky deletion ledgeru. Aktualizovat existující OAuth/MCP provozní dokumentaci dohledanou přes `rg --files docs tools/festapp`, nikoli vytvořit konkurenční specifikaci. Zachovat související vysvětlení form `is_open` versus `registrationMode`; neměnit business význam formulářů.

V `automation/ci/checks.json` doplnit pojmenovaný MCP auth kontraktní krok do existujícího `server-policy` jobu. Krok instaluje frozen `tools/festapp` a `web_client`, spustí choice/remote testy, oba web component testy, Deno mcp-session-exchange testy a `docs:check`. Nezavádět devátý release job ani kopii seznamu testů ve workflow. V `.github/workflows/image-upload-regressions.yml` přidat invokaci nového canonical kroku, potřebné Deno setup a push/PR path triggers pro `tools/festapp/**`, `packages/festapp_contracts/**`, `supabase/functions/mcp-session-exchange/**`, oba UI soubory a jejich testy, generátor/reference a přímo importované společné moduly. Stejné runtime požadavky musí umět lokální mirror. Nespoléhat na dosavadní zelené PR checks: MCP remote testy v dosavadním server-policy kroku nejsou.

Výstup: relevantní regrese běží z canonical CI i mirroru, reference odpovídá zdroji z aktuálního main, žádná stará listener cesta. Kontrola: `./automation/test_ci.sh server-policy web-startup` a podle skutečného diffu další dotčené canonical lanes; ověřit syntaxi více argumentů přes `--help`, případně spustit jednotlivě. Výsledek s přesným source SHA a seznamem checks zapsat do realizačního handoffu.

## Deletion ledger

| Cesta nebo chování | Finální akce | Důkaz absence |
|---|---|---|
| Původní best-effort `installConnectionReplacement` tělo | Nahradit synchronním transakčním adaptérem, bez swallow commit chyby | jediný owner aktivace/revokace, HTTP fault test |
| `activeConnections` bez issuance | Nahradit jednotným predicate | pending není v choices ani management listu |
| Vícekrokové autocommit `storage.revoke` | Nahradit atomickou revokací pro všechny callery | fault/restart test a cílené reference |
| Roční TTL backendu po pouhém consentu | Přesunout promotion do aktivace | pending deadline a restart test |
| Test očekávající success při chybě replacement cleanup | Nahradit fail-closed kontraktem | žádné HTTP 200 + neaktivovaný nástupce |
| Kopie duration/idle výpočtů | Odstranit ve prospěch společného vlastníka | scoped `rg` a reálné boundary testy |
| Ručně sloučená nebo zastaralá reference | Regenerovat | `docs:check` |
| Trvalé fallback větve pro chybějící issuance | Jednorázově normalizovat data; uchovat pouze záměrnou historickou policy | restart normalizace a všechny nové zápisy mají marker |

## Požadované ověření a definice hotovo

Při realizaci respektovat pnpm 11.24.0, frozen lockfiles, instrukce repo a jeden Flutter task na workstation. Tato práce sama nevyžaduje Flutter build. Testy sdružovat po koherentní změně; auth ověřovat `standard`, nikoli low-risk.

Základní cílené příkazy (po dependency install v příslušných package adresářích):

```sh
pnpm --dir tools/festapp exec node --test --test-concurrency=1 test/connection-choice.test.mjs test/remote.test.mjs test/forms.test.mjs
pnpm --dir web_client exec node --test --test-concurrency=1 tests/components/mcp_connection_page.test.js tests/components/account_connections_page.test.js
deno test --frozen --lock=supabase/functions/deno.lock --allow-env --allow-net --allow-read supabase/functions/mcp-session-exchange/
pnpm --dir tools/festapp run docs:check
```

Nutné nové scénáře, nikoli implementaci kopírující testy:

- A aktivní, B->A nikdy neexchange, C správně nabízí A; A zůstává funkční do úspěšné aktivace C. Pending expiruje i po restartu.
- Dva skutečné HTTP exchanges proti témuž target: právě jeden úspěch, druhý OAuth error; přesně jeden aktivní nástupce po restartu. Zopakovat při obráceném pořadí.
- Target se odvolá/exspiruje mezi consent a exchange: nevyhraje náhrada proti neaktivnímu cíli. Samostatně ztráta doménových práv: nové připojení nepřebírá starší oprávnění a živá SQL autorizace odmítne dotčené použití. Plán nepřidává síťový domain-rights lookup dovnitř synchronní SQLite transakce; neplést tuto kontrolu s lifecycle cíle.
- Neplatné PKCE, klient, profil, cizí connection ID, expirovaný/opakovaný kód nikdy neodvolají target. Nové nezávislé připojení žádný target neodvolává.
- SQLite selhání po odstranění backendu, po tombstone a před dokončením aktivace: rollback všech dotčených dat, HTTP error bez tokenů, staré připojení funkční, nové tokeny nepoužitelné i po restartu. Test pádu po commit uzná síťovou nejistotu, ale nepřipustí dvě aktivní připojení.
- Všechny 4 doby platnosti: reálný Grant/AccessToken/RefreshToken, časové hranice před/na/po expiry. Refresh neprodlužuje absolutní konec; 30denní neaktivita, úspěšný refresh posune pouze idle okno; neúspěšný refresh/status ne. Testy používat řízený čas, ne čekání na dny.
- Replay použitého refresh tokenu odmítne i aktuální rodinu, bez obnovení oprávnění. Backend session expiry/MFA vede k pravdivému reconnect stavu.
- Normalizace starých dat je idempotentní, nemění scopes ani konec, neodpojí nepoužité legitimní historické připojení a neudělá je automatickým replacement defaultem.
- Obě UI a bridge: 7denní default, explicitní 365 včetně write, pojmenování, návrat po chybě, pending status, odvolání. Žádné tajné hodnoty v HTML/logu.

Skutečné browser ověření při realizaci delegovat Terra do izolované muted headless session s lokálním disposable backendem podle příslušného skillu. Projít consent -> callback -> skutečný token exchange -> MCP request -> refresh -> revoke, plus druhé připojení a opuštěný flow. Pokud existující fixture dokládá jen render, nenazývat ji end-to-end připojením. Nepoužívat produkční účet/tenant pro vyplnění chybějícího lokálního důkazu. Chybějící prostředí je explicitní nedokončené ověření, ne skip maskovaný jako úspěch.

Hotovo znamená: aktuální PR změny v izolovaném worktree, všechny výše uvedené invariants a dotčené canonical mirror lanes doloženy, deletion ledger uzavřen, dokumentace a generovaná reference aktuální, zbývající omezení výslovně uvedena. Žádný záměrný skip k obejití auth regresí. Nemažte hodnotné testy jen kvůli čistému výstupu.

## Samostatná publikace a vydání

Při pozdější výslovné autorizaci publikace nejdříve znovu fetch main, zkontrolovat nový diff a opakovat dotčené checks. Zachovat PR #749; nevytvářet náhradní PR bez důvodu. Respektovat required reviews, nepoužívat admin bypass.

Před produkcí: všech osm canonical GitHub jobs zelených na přesném `baseMainSha` a `automation/ci/release_gate.py`. Určit potřebné issuer/web/Edge artefakty podle finálního diffu, pro kompatibilitu vydat nejdříve server schopný přijmout staré i nové payloady, potom vybraného web klienta. Ověřit GoTrue session omezení schváleného tenant targetu; lokální roční TTL test není důkaz jeho produkční session policy. Zachovat volume a klíče; zálohu/restore úložiště řešit jako credentials, nic nelogovat. Rollback nesmí obnovit neatomický replacement writer nad novým storage stavem - přednost má oprava vpřed, při nutném návratu nejprve zastavit issuer a obnovit kompatibilní snapshot s posouzením již odvolaných grantů. Neukládat do plánu příkaz k automatickému oživení starých credentialů.

Aktuální plán nemá blokátor pro lokální implementaci. Neověřené jsou produkční nasazení případných neveřejných verzí PR a efektivní GoTrue timeouty; jejich kontrola patří do samostatně autorizované přípravy vydání.
