# Google přihlášení ve FestAppu

Datum: 2026-10-01  
Stav: Zpřesněný plán pro další session; prefix a vydání session ověřeny na izolovaném GoTrue v2.189.0. Google OAuth E2E, plná aplikační integrace a produkční rollout dosud neprovedeny.  
Verification: standard (autentizace, oprávnění, migrace).  
Výchozí bod: `main`, HEAD `b7b62b899`, pracovní strom obsahoval jiné rozpracované změny. Tento úkol přidává pouze plán, předávací prompt a referenční screenshoty.

## Výsledek a rozsah

Uživatel zvolí „Pokračovat s Google“, vybere Google účet a vrátí se do stejného kontextu FestAppu. Zůstanou jeho vstupenky, členství, rozpracovaná cesta i oprávnění. Nový uživatel může dokončit registraci pouze tam, kde ji organizace povoluje. Existující účet se při prvním propojení ověří dosavadní přihlašovací metodou; další přihlášení už proběhne přes Google.

Rozsah implementace: vanilla JS web klient, Flutter web a mobilní adaptéry Android/iOS, společná serverová hranice, bezpečné propojení účtů, dokončení nové registrace, jednotná vizuální kvalita. První provozní cíl je `vstupenky.online`; další tenanty nepovolovat ani nevydávat automaticky. Konkrétní produkční větev vyřešit z tenant overlay evidence při release, ne odhadem z `main`.

Neprovádět globální sjednocení uživatelských UUID, přepis RLS na nový model účtů, změnu ticket ownership, odstranění hesel/QR, Google One Tap, přístup k Drive/Gmail ani rollout všech `prod/*`. Apple provider není součástí tohoto zadání; iOS publikace má samostatnou podmínku níže. Plán není souhlas s deployem, změnami Google Console, commitem ani pushem.

## Ověřený současný stav

| Fakt | Zdroj | Dopad |
|---|---|---|
| Auth email má prefix organizace, např. `1+jan@example.com`; `user_info` patří jedné organizaci. | `database/functions/users/create_user_in_organization_with_data_pure.sql`; `AuthService.validateCurrentOrganization()` | Google email není současná Auth identita. Prosté zapnutí `signInWithOAuth` nesplňuje zachování účtů. |
| Přihlášení heslem prefix doplňuje už na klientovi. | `lib/components/users/views/login_page.dart`, `AppConfig.getUserPrefix`; `web_client/src/components/users/login_modal.js` | Zachovat současnou cestu i identifikátory. |
| Stejná schránka může obsluhovat více lidí přes `+N` aliasy. | `lib/components/users/README.md`, `allocate_user_sign_in_email.sql` | Nepárovat přes `email_delivery`, neodstraňovat plusy ani tečky z adres. |
| Flutter dokončuje login synchronizací práv, privátní cache, programu a notifikací. | `lib/data_services/auth_service.dart`, `_finalizeLogin` | Google musí projít touto hranicí, ne pouze uložit token. |
| Ověření organizace při síťové chybě nyní vrací true. | `AuthService.validateCurrentOrganization()` | Nový login/propojení potřebuje striktní online kontrolu. Zachovat zvlášť existující offline obnovu. |
| Web login má vlastní modal, AuthService a předání session do Flutteru. | `web_client/src/components/users/login_modal.js`, `services/auth_service.js`, `public/auth_bridge.html`, `lib/services/auth_handoff_web.dart` | Callback nesmí předčasně převzít router/bridge ani spustit dvojí dokončení. |
| QR login umí vydat standardní Supabase session existujícímu uživateli. | `supabase/functions/exchange-login-qr/exchange.ts`: Admin `generateLink`, anon `verifyOtp` | Existující vzor, ale nepřebírat beze změny: lokální důkaz odhalil implicitní signup a sdílený recovery slot. Cílový mechanismus popisuje D5. |
| Registrace vytváří také vlastní unit a její manažerské členství. | `database/functions/users/create_user_from_registration.sql`, `supabase/functions/register/` | Google registrace musí zachovat tyto účinky, ale neposílat náhodné přihlašovací heslo emailem. |
| Mobilní manifest obsahuje pouze zakomentované webové intent filtry; iOS plist nemá nalezenou URL callback registraci. | `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist` | Mobilní návrat je explicitní implementační práce. |
| Canonical endpoint je `api.festapp.net`; runtime používá GoTrue v2.189.0. | `docs/architecture/ai_context.md`, `automation/hetzner-supabase/runtime/docker-compose.festapp.yml` | Ověřit skutečně nasazenou konfiguraci a tenant activation před provozními úkony. |
| Rehearsal konfigurace vypíná signup v GoTrue. | `runtime/configure-rehearsal-env.py` | Není důkaz produkčního nastavení. Nevypínat tuto ochranu globálně kvůli Google. |

Aktuální `CONTRIBUTING.md` obsahuje historické pokyny ke cloudovým zdrojům. Pro výběr backendu platí novější explicitní pravidla `ai_context.md`: activation dokument, canonical generace a organizace. Staré cloudy nejsou migrační cíle.

## Reference a závazný vizuální brief

Dne 2026-10-01 bylo otevřeno veřejné nepřihlášené UI obou webů. Neproběhl Google login ani ověření backendu Mendelia. Lokální `mendelionet-sdk` obsahuje Voice API/CLI, nikoli prokázanou implementaci webového Google loginu. Mendelio je proto ověřená UX reference, nikoli převzatá autentizační architektura.

- [Mendelio login](google-sign-in-reference-2026-10-01/mendelio-login.png): modal, přepnutí login/registrace, Google a Apple nad formulářem, oddělovač, konzistentní pole a loading. Snímek má omezenou výšku viewportu a není důkazem celého obsahu ani mobilního layoutu.
- [Současný vstupenky.online login](google-sign-in-reference-2026-10-01/vstupenky-login.png): kompaktní centrovaná karta, modré akce, tlumené pozadí s blur, jednoduchá typografie a hierarchie. Referenční snímek je tmavý režim.
- Kód designu: `web_client/src/theme_config.css`, `services/theme_service.js`, `components/shared/modal_styles.js`, `components/ui/modal.js`. Flutter protějšky: `lib/theme_config.dart`, `lib/styles/styles_config.dart`.

### Cílové UI

Zachovat styl tenantova webklienta, nepřenášet barevnost ani dekorace Mendelia. Změna musí být souvislý návrh přihlášení, ne osamocené tlačítko přilepené k formuláři.

```text
                       Přihlásit se                   [Zavřít]
             Přihlaste se ke svému účtu FestApp.

                 [ G  Pokračovat s Google ]
                 --------- nebo ---------
                 E-mail
                 [                       ]
                 Heslo
                 [                    oko]
                 [     Přihlásit se      ]
             Zapomenuté heslo    Registrovat se
```

| Prvek | Realizační smlouva |
|---|---|
| Modal / Flutter panel | Web ponechá výchozí šířku 400 px, max. 90 % viewportu a 90vh, vnitřní scroll, radius 12 px a backdrop z `Modal`. Flutter napodobí stejnou hierarchii v existující responsive stránce. |
| Typografie a barvy | Čerpat skutečně aktivní tenant theme. Repo výchozí tokeny obsahují Futura, primary `#4465A6` / dark `#80BDF2`, spacing 8/16/24. Tyto hodnoty nejsou univerzální hardcoded brand všech tenantů. |
| Google tlačítko | Plná šířka, min. 44 px výška, originální vícebarevné G, korektní light/dark varianta podle Google brand pravidel. Neobarvovat G tenantovou barvou. |
| Formulář | Zachovat autocomplete, zobrazení hesla, inline validaci; existující radius polí 6 px sladit mezi akcemi a poli. CTA i loading mají stabilní rozměr. |
| Rozestupy | Google/oddělovač/formulář 16-24 px, žádné nesourodé mezery ani layout shift. |
| Nový účet | Stejné Google tlačítko také v registraci; následně jen chybějící údaje a existující povinné souhlasy. Profilové jméno z Google nabídnout jako editovatelný návrh. |
| Propojení | Stejný panel, jasná věta „Pro propojení nejprve ověřte svůj stávající účet.“ Heslo nebo současná obnova; nestrašit duplicitním účtem ani nepředstírat dokončený login. |
| Stavy | idle, openingGoogle, completing, needsAccountProof, needsProfile, success, cancelled, retryableError. Zrušení Google není „Neplatné heslo“. Chyba sítě poskytne opakování; expirovaný pokus začne znovu. |
| Přístupnost | Skutečný button pro zavření, accessible dialog name, focus trap a návrat focusu, Escape, čitelné focus ringy, oznámení loading/error, reduced motion a 200% zvětšení. |
| Responsivita | Důkaz na 360, 390, 768 a 1440 px; krátký viewport, soft keyboard a landscape bez useknuté akce. Ověřit light/dark, češtinu i angličtinu. |

Styly scopingem omezit na auth komponentu. `SHARED_MODAL_STYLES` dnes obsahuje obecné selektory `input`, `label`; jejich rozšíření nesmí nechtěně změnit checkout a ostatní dialogy. Nevytvářet paralelní sadu globálních CSS ani měnit celý design systém.

Před finálním zapojením dodat screenshoty realizovaného loginu, registrace, propojení a chyby. Vizuální kvalita je přijímací podmínka, ne dobrovolné polish na konci.

## Architektura a rozhodnutí

### D1: Zachovat tenantové účty, použít Google OIDC broker

Zvolená cesta: Google ověří identitu na serveru, FestApp ji přiřadí konkrétnímu existujícímu tenantovému UUID a vydá běžnou Supabase session. SQL/RLS, ticket ownership ani emailové prefixy se nepřepisují. Google provider v GoTrue není druhá paralelní login cesta.

Důvod: běžný Supabase OAuth vytváří/linkuje Auth identity podle vlastního globálního modelu. Zde jedna osoba může mít různá UUID v různých organizacích a skutečný Google email není Auth email. Přímý OAuth by vyžadoval širší migraci identity modelu. Broker je více bezpečnostní práce, ale má ohraničený dopad. Použít udržovanou OIDC/JWT knihovnu, nikoli ruční kryptografii.

### D1a: Přesná smlouva emailů a prefixu

Prefix není výjimka v Google OAuth. Nejdříve server ověří nezměněný Google token a teprve potom převede aplikační identitu na účet Supabase. Změna `email` uvnitř podepsaného tokenu by zneplatnila podpis. `signInWithIdToken` nemá parametr pro přesměrování identity na libovolný prefixed účet.

| Vrstva | Příklad organizace 1 | Vlastník |
|---|---|---|
| Ověřená Google identita | issuer + sub; email `jan@gmail.com` | Google, pouze validované claims |
| Aplikační přihlašovací adresa | `user_info.email_readonly = jan@gmail.com` | Stávající FestApp profil |
| Doručovací adresa | `email_delivery`, jinak `email_readonly` | `get_user_delivery_email`; nikdy tenantový prefix |
| Supabase Auth adresa | `auth.users.email = 1+jan@gmail.com` | Kanonický identity writer |
| Supabase session | `user.id` / JWT `sub` = původní UUID FestApp účtu | GoTrue; není to Google sub |

Serverový formát pro NOVOU identitu je `decimal(organizationId) + '+' + lower(trim(signInEmail))`. Přidání proběhne právě jednou v `create_user_in_organization_with_data_pure`; broker této funkci předá NEPREFIXOVANOU adresu. Nový čistý SQL helper `public.format_auth_email(p_organization bigint, p_sign_in_email text)` sjednotí konstrukci v identity writeru a resolveru. Není to autorizační funkce. Klientský password login dál používá existující formatter; společné fixture kontrakty musí dokazovat shodný výsledek Dart/JS/SQL.

`organizationId` pochází z povoleného serverového tenant/client záznamu svázaného s pokusem. Browser posílá tenant identifikátor jako návrh, server jej ověří; ani `Origin`, libovolný `Host`, Google `hd`, metadata nebo číselný prefix zaslaný uživatelem samy nezakládají důvěryhodnou organizaci. Organizace se po zahájení pokusu nedá přepnout.

Pro EXISTUJÍCÍ identitu dohledat `user_info` ve vybrané organizaci a připojit `auth.users` přes UUID. Ověřit, že uložený Auth email odpovídá kanonickému formátu jejího `email_readonly`, že účet není banned/deleted a že link patří témuž UUID. Mint používá tuto DB-resolved adresu, nikoli nově zkonstruovanou adresu z aktuálního Google emailu. Nesoulad znamená `account_identity_inconsistent`, bez automatické opravy, změny emailu nebo vytvoření náhradního účtu.

| Vstup | Výsledek / povinné chování |
|---|---|
| org 1, `jan@gmail.com` | `1+jan@gmail.com` |
| org 2, stejný Google email | `2+jan@gmail.com`, jiné UUID; žádné spojení účtů napříč organizacemi |
| org 1, účet `jan+1@gmail.com` | `1+jan+1@gmail.com`; alias je samostatný člověk/účet |
| org 1, skutečný email `1+jan@example.com` | `1+1+jan@example.com`; nejde o dvojité prefixování, první `1+` je součást reálné adresy |
| ` Jan@Example.com ` při založení | `1+jan@example.com`; normalizace odpovídá stávajícímu SQL |
| Google účet má nový email, známý sub | Stejný FestApp UUID a uložený Auth email; neprovádět automatický email update |
| Chybějící/invalidní org nebo více odpovídajících profilů | Odmítnout; nevybírat první řádek ani odhadovat organizaci |

Nikdy heuristicky neodstraňovat `^\d+\+`, neodstraňovat Gmail tečky, nekanonizovat `googlemail.com` na `gmail.com`, nepřepisovat `+N` a neodvozovat tenant z emailu. Helper nepřijímá směs raw/prefixed emailů; typ hranice a název parametru určují význam. Otestovat maximální délku výsledného emailu podle reálného GoTrue validatoru, aby nový účet nevznikl přes SQL s adresou, kterou následně Auth API odmítne.

### D2: Identita se váže podle issuer + sub + organizace

Nová tabulka `public.external_login_identities` obsahuje organization, user_id, provider, issuer, subject, created_at. Unikátnost `(organization, provider, issuer, subject)` a `(organization, user_id, provider)`. Vynutit vztah user_id ke stejné organizaci a FK s odstraněním při smazání účtu. Google `sub` je identifikátor; email je pouze údaj pro návrh registrace. Změna emailu nesmí přesunout link na jiného uživatele.

Žádné automatické propojení podle emailu, `email_delivery`, display name ani client metadata. I přesná emailová shoda vyžaduje jednorázové ověření existujícího FestApp účtu. Propojení z nastavení účtu vyžaduje čerstvé ověření, nikoli pouze starou uloženou session. Ověřená Google identita se nesmí přepsat, pokud už je připojena jinam. Existující vazba vede přímo k loginu bez hesla.

### D3: Jedna serverová hranice a jedno dokončení session na platformu

Navrhované nové entrypointy:

- `supabase/functions/google-auth-start/`: zahájí pokus pro aktivovaný tenant/client a vrátí autorizační URL; server ověří povolenou organizaci, platformu a callback.
- `supabase/functions/google-auth-callback/`: Google code exchange, state/nonce a token validace; pouze krátký handoff kód do aplikačního callbacku.
- `supabase/functions/google-auth-complete/`: klient předloží jednorázový kód a svůj verifier; výsledek `authenticated`, `needs_account_proof`, `needs_profile` nebo typovaná chyba. Dokončení propojení/registrace je pokračování téhož pokusu s dalším ověřením.
- `supabase/functions/_shared/googleAuthFlow.ts`: jediný vlastník flow, provider ověření a orchestrace. `google-auth-*` nesmí kopírovat business logiku.
- SQL v `database/functions/users/`: atomické vytvoření/claim/consume pokusu, propojení identity a dokončení nové registrace. Service-role-only RPC pro externě ověřené identity; `anon` ani běžný JWT nesmí dodávat důvěryhodný Google subject.

Do Flutter `AuthService` přidat veřejnou úzkou metodu `completeExternalLogin`, která přijme serverem vydanou session, ověří online organizaci a použije `_finalizeLogin`. JS ekvivalent dokončí `setSession`, ověření profilu/tenanta a `_onLoginSuccess`. Dvojí callback, refresh event a opakovaný mount musí vést k jedinému dokončení a navigaci. Google token se nikdy nestane aplikační Supabase session přímo.

### D4: Rozhodovací tabulka pro stávající a nové účty

Po validaci Google claims nejdříve hledat link `(organization, google, canonicalIssuer, sub)`, až potom řešit email. Povolené Google issuer varianty normalizovat na `https://accounts.google.com` až PO kryptografické validaci issuer allowlistu.

| Situace | Serverové rozhodnutí | Co se změní |
|---|---|---|
| Link existuje, účet aktivní | `authenticated` | Jen nová session; žádná změna profilu, emailu, členství nebo hesla |
| Link neexistuje, přesný email již v tenantovi je | `needs_account_proof` | Do prokázání vlastnictví nic nevytvářet; nevydat druhý účet |
| Link neexistuje, email nenalezen, uživatel už účet má pod jinou adresou/aliasem | Nabídnout „Propojit existující účet“ a ověřit jeho přihlašovací adresu a heslo | Link na prokázané UUID; Google email nemusí být shodný |
| Link neexistuje, email nenalezen, registrace povolena | `needs_profile`, poté atomické vytvoření | Auth user, email identity, user_info, vlastní unit/member a Google link v jedné DB transakci |
| Registrace vypnuta | Nabídnout pouze propojení existujícího účtu | Žádný nový účet ani automatické členství |
| Email již obsadil souběžný import/registrace | `needs_account_proof` | Nevolat alias allocator jako řešení kolize Google signup |
| Google sub již propojen k jinému UUID v tenantovi nebo UUID má jiný Google link | `identity_already_linked` | Žádný overwrite ani sloučení dat |
| Neexistuje profil, ale Auth email již existuje | `account_identity_inconsistent` | Žádný adopt orphan account ani auto signup |

**Account proof:** při operaci `prove_existing` klient předá raw sign-in email a heslo přes HTTPS no-store. Server dohledá organizaci/profil, přes oddělený anon GoTrue client provede `signInWithPassword` s uloženým prefixovaným emailem a ověří returned UUID. Nepoužívat globální Supabase client s mutable session. Heslo nikdy nelogovat, neukládat, nevracet; rate limit nejméně podle pokusu, cíle a důvěryhodného source IP. Starý JWT nebo čerstvě refreshnutý JWT nejsou důkaz nového ověření. Transakce pro link ověří stejný cílový UUID i pokus a při konfliktu nic nepřepíše. Kontrola ownership není kontrola email equality.

Při zapomenutém hesle použít současný `send-reset-password-link` a `user_reset_token` flow. Po změně hesla znovu provést account proof; pokud Google pokus expiroval, opakovat Google. Nedávat do reset URL Google tokens ani continuation secret. QR přihlášení samo není automatický souhlas s připojením permanentní nové identity. Je-li na účtu MFA, dokončit požadovanou výzvu; nikdy vydávat AAL2 na základě samotného Google/OTP důkazu. UI nastavování/odpojování nesmí vycházet z GoTrue `providers`, protože Google vazbu vlastní FestApp tabulka.

**Nový účet:** sign-in email pochází pouze z ověřeného Google důkazu a případného mailbox proof svázaného s tímto pokusem. Běžný profilový payload jej nesmí přepsat. Změna navrženého emailu vyžaduje novou samostatnou verifikaci; nevytvářet účet pro libovolnou adresu zaslanou z formuláře. Registrační politika se kontroluje ve stejné transakci jako zápisy a chybějící/null flag musí znamenat zákaz. Sdílený domain initializer zachová současné vlastní-unit účinky. Přímé volání stávajícího veřejného registration RPC service-role klientem není náhradou nové striktní policy (současné `IF NOT flag` má při NULL trojhodnotovou logiku). Použít stávající organization email advisory lock; další pořadí zámků sjednotit na attempt -> organization email lock -> identity/user, stejně v link/create cestách. Unikátní constraints jsou poslední ochrana při více instancích.

Google `email_verified` není pro externí adresy vždy důkaz současného vlastnictví schránky. Pro nový Gmail nebo ověřený Workspace účet lze použít Google důkaz; jiný email vyžaduje čerstvý jednorázový mailbox proof před prvním zápisem účtu. Navrhnout ho přes existující `emailDelivery` a krátkodobý kód/pokus (hash s keyed HMAC pro nízkoentropický kód, nejvýše 5 pokusů, expirace nejpozději s Google pokusem), bez dočasného vytvoření Auth účtu. Tato kontrola neplatí místo account proof u existujícího účtu. Nezobrazovat cizí profily ani `email_delivery` během výběru.

### D5: Vydání Supabase session pouze pro existující UUID

**Ověřená korekce původního návrhu:** Admin `generateLink(type: magiclink)` vytvořil v lokálním GoTrue v2.189.0 chybějícího uživatele i při `GOTRUE_DISABLE_SIGNUP=true`. Prostý preflight existence má závod s account deletion a nestačí. Proto cílový sdílený issuer používá `generateLink(type: recovery)` následovaný serverovým `verifyOtp(type: recovery, token_hash: ...)`. Při chybějícím účtu vrátí 404 a nic nezaloží. Původní účet získal normální refreshovatelnou session, heslo zůstalo stejné; token má `aal1` a `amr: otp`. Důkaz a jeho limity jsou níže.

`recovery` je interní typ GoTrue proof, nikoli produktový reset hesla. Admin API neodesílá zprávu; proof se spotřebuje server-server a klient obdrží pouze finální session. Browser nikdy nenavštíví recovery action_link a nesmí otevřít reset UI. Ověřit SDK `setSession`/Auth events ve Flutteru i JS, protože HTTP důkaz sám client event chování nedokazuje. Google audit evidovat vlastním omezeným eventem; GoTrue jej bude evidovat jako OTP/recovery, ne jako Google provider.

Zavést úzký `_shared/issueExistingUserSession.ts` s kontraktem `{targetUserId, expectedAuthEmail}` -> ověřená session. Před i po mintu porovnat target UUID a živý profil/link v dané organizaci. Při nesouladu session nevracet; případnou vydanou session bezpečně revokovat. Nikdy ručně zapisovat `auth.sessions`, `auth.refresh_tokens` ani podepisovat aplikační JWT.

**Souběh:** magiclink i recovery sdílejí `auth.users.recovery_token`; druhé vygenerování zneplatní první. Single-flight v prohlížeči nebo Edge procesu nestačí. Service-role-only tabulka krátkých lease pro cílové UUID serializuje generate+verify napříč instancemi. Lease má náhodného ownera, expiraci, atomický acquire/release a omezený wait; starý owner nesmí uvolnit novou lease. Lease timeout musí přesahovat timeout dvojice HTTP operací, po nejistém timeoutu se nesmí předčasně uvolnit. Lost lease/pozdní odpověď se nesmí vydat klientovi. Otestovat souběh i vypršení lease; bezpečný výsledek může být typovaná retryable chyba, nikdy nesprávná identita.

Stejný issuer/lease musí používat všichni zjištění producenti: `exchange-login-qr/exchange.ts` a `cancel-reception-registration/cancel.ts` (ten získává session pro následný global signout). Zachovat jejich oprávnění, membership kontroly, revokační receipt i veřejné payloady. Google login po zrušení účasti neopravňuje vrátit odebrané členství. Případný souběžný nativní GoTrue recovery endpoint mimo tento lease může pořád invalidovat OTP; ošetřit bounded retry novým pokusem, bez vydání původního proof dvakrát. FestApp password reset v aktuálním repozitáři používá vlastní `user_reset_token`, ne GoTrue recovery link.

**Implementační doplnění 2026-10-02 - MFA:** SQL resolver eviduje ověřené MFA faktory. Recovery issuer odmítne MFA login před vytvořením OTP (revokační účel smí pouze revokovat). Broker pro MFA vyžádá čerstvé heslo původního UUID, uchová proof session pouze šifrovaně v attemptu a provede skutečný GoTrue TOTP/phone challenge. Až serverové verify a kontrola AAL2 dovolí propojení/odpojení nebo návrat této session do stejného klientského finalizeru. Nevydává mezilehlou AAL1 session klientovi a nepodepisuje vlastní JWT. Lokální digest-pinned důkaz pokrývá skutečný TOTP; SMS a živý Google/device E2E jsou release kontroly. Reprodukovatelné SDK/SQL/console důkazy a přesné zbývající kroky jsou v `docs/operations/auth/google-sign-in.md`.

### D6: Pokus, jednorázový callback a pokračování formuláře

Oddělit jednorázový handoff od více kroků UI. `start` vydá attempt id a URL navázanou na client challenge. Broker nastaví browser binding cookie při top-level vstupu na jeho origin, ne cross-site fetch třetí strany; callback ji ověří. To je nutné i při startu ze vstupenky.online a v Safari. Multi-tab pokusy nesmí přepisovat state jeden druhému. Cookie je host-only Secure HttpOnly SameSite=Lax, s TTL a omezeným počtem otevřených pokusů; callback je top-level GET. Přesný bootstrap start/redirect otestovat před UI wiringem.

`complete` spotřebuje 60sekundový handoff právě jednou. Pokud je nutný profile/account proof, vrátí krátkodobý opaque continuation secret, jehož hash je v attempt row a který se při každém úspěšném state transition rotuje. Continuation se posílá jen POST body s klientským verifierem, nikdy URL; celková expirace se neprodlužuje nad 10 minut. Při ztrátě odpovědi nebo překryvu tabů začít nový pokus, zachovat pouze bezpečné neautentizační drafty.

Stavy: `created -> provider_verified -> awaiting_account_proof | awaiting_profile | ready -> issuing -> consumed`; alternativně `cancelled/expired/failed`. Z `issuing` nelze neomezeně znovu mintovat. Typované chyby: `provider_cancelled`, `attempt_expired`, `invalid_provider_proof`, `account_proof_failed`, `registration_disabled`, `identity_already_linked`, `account_identity_inconsistent`, `auth_temporarily_unavailable`. Detail interního účtu patří pouze do minimálního audit eventu, ne veřejného chybového textu. Úklid lease/pokusů zahrnout do provozního jobu a account deletion domain fáze; pouze FK na `auth.users` nestačí, protože public profil mizí dříve než Auth user.

### Bezpečnostní a lifecycle kontrakt

1. Jen scopes `openid email profile`. Google client secret zůstává na serveru. Žádné dlouhodobé Google access/refresh tokeny v DB; bez offline Google access.
2. Podepsaný ID token ověřit přes Google JWKS: algoritmus allowlist, podpis, issuer, audience/authorized party, exp/iat, nonce, neprázdný sub, `email_verified`. Nečíst claims z prostého decode jako důkaz.
3. Pokus navázat na browser state, tenant, client/platform, schválený redirect a klientský challenge/verifier. Serverový state/nonce náhodný; povinný browser binding a top-level cookie bootstrap podle D6. Samotný `state` bez vazby na zahajující browser není hotové řešení. PKCE S256 pro code flow dle podpory klienta; samostatný verifier chrání finální handoff.
4. `external_login_attempts` ukládá hash state/handoff/challenge, tenant, status, expiraci a cílovou identitu; žádné dlouhodobé tokeny. Nutný serverový code verifier ukládat krátkodobě šifrovaně. Pokus 10 minut, dokončovací kód 60 sekund, atomický claim/consume. Recovery/propojení po expiraci vyžádá nový Google důkaz.
5. Callback URL v Google Console: navržená `https://api.festapp.net/functions/v1/google-auth-callback`, nikoli GoTrue `/auth/v1/callback`. Zvláštní rehearsal endpoint/client. Přesnou routu a dostupnost veřejného callbacku potvrdit integračním spike před UI wiringem.
6. Klientské callbacky mají vlastní routu zpracovanou před obecným routerem. Jen předem povolené HTTPS origins / mobilní app links. Return path musí být lokální povolená route; odmítnout `//host`, jiný scheme, encoded bypass. Zachovat pouze bezpečný route/occasion kontext, žádná hesla nebo platební data v URL.
7. Session vydat výhradně pro SQL-resolved UUID/authEmail; Sdílený issuer `generateLink(recovery)` + `verifyOtp(recovery)` podle D5. Před i po vydání ověřit existenci uživatele/profilu, ban/deletion, organizaci a revokaci vazby. Výsledné session.user.id musí odpovídat cíli. Zakázat magiclink typ ve sdíleném issueru: recovery typ musí při neexistujícím účtu selhat bez signup.
8. Vydání session a SQL transakci nelze spojit atomicky. Claim uzamkne pokus před mintem; při nejistém výsledku se kód znovu nepoužije, uživatel bezpečně opakuje login. Úspěšný link/profil zůstává idempotentní. Nedostupnost odpovědi nesmí vytvořit další účet nebo unit. Konflikty souběhu vrací definovaný výsledek, ne overwrite.
9. Refresh/access tokeny pouze v HTTPS no-store odpovědi complete, nikdy URL, screenshot, log nebo analytika. Callback okamžitě očistí query přes replace; bez třetích stran, `Referrer-Policy: no-referrer`, žádné cachování. CORS konkrétní origins; rate limiting start/callback/complete a account proof.
10. Registrace ověřuje serverový `IS_REGISTRATION_ENABLED = true` (missing/null odmítnout), případně povinné profilové údaje a existující souhlasy. Nevstupuje automaticky do události ani nenavyšuje role. Vytvoření vlastní unit zachová jen dosavadní registrační práva.
11. Sdílet existující registrační SQL invarianty a zamykání emailu. Google účet může používat kryptograficky náhodné nedistribuované heslo stávajícího identity writeru; heslo nesmí být deterministické ani odvozené z Google tokenu. Obnova hesla zůstává současnou cestou. Existující účty/profile se při loginu nepřepisují Google metadata.
12. Odpojení Google až po čerstvém ověření alternativní metody; nikdy neodpojit jedinou dostupnou metodu. Vazba i pokusy musí být součástí account deletion a případné revokace. Kontrola na serveru platí i pro staré klienty.
13. Nové tabulky RLS + explicitní grants, helpery `public` se `search_path = public, extensions`. Žádné persistentní aplikační triggery. Expirace v každém čtení; úklid pokusů explicitní runtime jobem, např. hourly, hard-delete nejpozději 24 hodin po expiraci.

## Implementační vlny

### 1. Ověřit hranice a zprovoznit izolovaný auth spike

**Změny:** přečíst pravidla, zkontrolovat pracovní diff, načíst tenant overlay mapování pro budoucí vstupenky rollout. Bez čtení produkčních osobních dat vyřešit callback routing, service-role-only SQL a vydání session pro syntetický existující prefixed účet na isolated/rehearsal Auth. Ověřit browser CSRF binding a mobilní návrat technickým prototypem. Navázat na níže uložený lokální důkaz, neopakovat jeho průzkum bez důvodu. Doplnit dosud neověřené tenant RLS, callback, SDK eventy a runtime digest. Zkontrolovat account deletion domain fázi a password recovery kontrakt před přidáním vazeb.

**Migrace/mazání:** žádná produkční změna; spike není druhá produkční implementace a po důkazu se odstraní nebo přesune do integračního testu.

**Validace:** skutečný GoTrue mint/refresh/revoke pro syntetickou identitu, odmítnutí jiné organizace, žádný nový auth user při mintu. Mock test sám tento kontrakt nedokazuje.

**Exit:** dokumentovaný průchod Google/OIDC proof -> původní UUID -> validní standardní session; vyřešená callback cesta. Pokud spike vyvrátí návrh, nejprve aktualizovat tento plán, ne přidat fallback na globální OAuth účty.

### 2. Backend a data

**Změny:** nové identity/attempt/session-lease tabulky, unikátní klíče, grants/RLS a receipted RPC podle D1a-D6, verzi SQL zapsat jako canonical soubory i unikátní timestamp migration. Nové Edge entrypointy a `_shared` vlastník; úzký session issuer povinně sdílet s QR a revokací účasti podle D5 bez změny veřejných kontraktů. Sdílet registraci/profile/unit inicializaci s `create_user_from_registration`, ne duplikovat její SQL. Doplnit bezpečné propojení/odpojení, mailbox proof pro externí Google emaily a account deletion včetně public domain fáze. Zavést SQL email formatter; neprovádět hromadný backfill prefixů.

**Provozní evidence:** aktualizovat `supabase/functions/test-coverage.json`, `_shared/edgeEntrypoints_test.ts`, `automation/hetzner-supabase/merge/runtime-writer-policy.json`, příslušné policy/coverage testy a `docs/backend/edge_functions.md`. Současný text „QR je jediná anonymous exception“ musí být upraven o přesně vymezené Google proof endpointy. Prověřit runtime gateway JWT exemptions, nestačí klientské CORS.

**Migrace/mazání:** pouze přidání schema; žádný backfill Google linků podle emailu, žádná změna UUID nebo email prefixů. Proof tables nepovolují anonymní přímé zápisy.

**Validace:** SQL transakční testy pro dvě organizace, aliasy, souběh a smazání; Edge testy nevalidních JWT/state/nonce/audience, replay, rate limit, redirect bypass a partial failure. Povinné regresní testy QR/registrace/cancel-reception, protože se mění společný issuer a registrační hranice. Prokázat fail-closed null registration flag a konflikt Google signup s importem.

**Exit:** žádný klient nemůže zvolit libovolný user_id/sub/organization a získat session; jeden pokus nevytvoří dva účty/unit ani dvě vazby.

### 3. Web klient a grafika

**Změny:** `login_modal.js`, auth-scoped styly, `auth_service.js`, callback zpracování ve startup/router hranici, překlady v existujícím workflow (`CommonStrings`, cs/en zdroje). Stejné Google CTA v login i registraci; navazující profile/link views. Schopnosti Google pro tenant načítat z backendu, ne pouze z build flagu. Pro web použít plný redirect s obnovou omezeného route kontextu; žádné automaticky otevírané popupy ani One Tap.

**Kompatibilita:** neztratit rozpracovaná formulářová data při odchodu; před přesměrováním zachovat existující draft mechanismus nebo záměr bezpečně nabídnout potvrzení opuštění rozpracovaného formuláře. Hesla neukládat. Upravit skutečnou async kontrolu `AuthService.isLoggedIn()` (dnes boolean nad Promise) tam, kde ji nové pokračování potřebuje.

**Migrace/mazání:** využít stávající modal a post-login navigaci, ne druhou login aplikaci. Nové callbacky nepřevádět přes legacy token hash větev v auth bridge. Existující bridge zachovat pro jeho ostatní volající.

**Validace:** Node testy login modalu, auth callbacku a bridge; izolovaný browser scénář návratu ke konkrétní události. Screenshoty dle vizuální matice, focus/keyboard check. Žádný live signup při pouhé UI kontrole.

**Exit:** web login, propojení i nová registrace mají sjednocený vzhled a typed stavy; po dokončení správné rights a původní route.

### 4. Flutter web a mobilní aplikace

**Změny:** Google action a navazující stavy v `login_page.dart` / `signup_page.dart`, `AuthService.completeExternalLogin`, single-flight koordinátor callbacku, `lib/main.dart` startup a `lib/router_service.dart` navigace, lokalizace přes `UserStrings`. Využít existující theme a form komponenty. Striktní ověření nově vydané session oddělit od tolerantní offline obnovy.

**Mobilní integrace:** systémový prohlížeč/auth session, žádný embedded WebView pro Google. Ověřené Android App Links / iOS Universal Links s tenantově generovanými manifesty, `assetlinks.json` a AASA. Uložit krátkodobý verifier pro cold start do secure storage, odstranit po dokončení/expiraci. Vše, co generuje `apply_config.sh`, měnit v config/template zdroji. Ověřit různé aplikace/podpisy bez automatického vydání dalších tenantů.

**Migrace/mazání:** žádná změna heslových/QR vstupů; nenechat dvě alternativní finalizace Google loginu. Token callback neřešit ručním parsováním Google JWT v UI.

**Validace:** targeted Dart analyze + Flutter testy AuthService/callback/post-login navigace. Na zařízení ověřit Android cold/warm start, back/cancel a refresh po restartu; iOS stejná matice před jeho vydáním. Flutter web i JS klient nesmí přebírat stejný callback dvakrát.

**Exit:** všechny implementované platformy vrací původní identitu a synchronizují privátní data právě jednou. Neotestovaná platforma se nesmí vykázat jako hotová.

### 5. Připravenost, konfigurace a postupné nasazení

**Změny:** runbook pro OAuth consent screen, domény, minimum scopes, client/secret rotation, přesné callback URLs, runtime capability a rate limits. Žádné sdílení Mendelio client secretu. Při release ověřit canonical activation, tenant ID a organizaci, nasadit schema -> Edge/runtime -> callback klienty -> povolit jednu organizaci. Ověřit Google app publishing/test users a dostupnost pro běžný účet.

**iOS gate:** Apple 4.8 může vyžadovat ekvivalentní privacy-preserving login, typicky Sign in with Apple. Mendelio jej v UI nabízí. Před iOS publikací doložit konkrétní výjimku nebo samostatně schválit a naplánovat Apple provider. Tento plán automaticky nerozšiřuje zadání na Apple; iOS lze implementovat, ale release zůstane pending, dokud gate není vyřešen.

**Validace:** syntetický test účet existující i nový, heslo/QR/obnova/odhlášení, refresh, Google cancel, server failure, správné membership a absence tokenů v logu. Produkční smoke a testovací data jen v rámci samostatně autorizovaného release.

**Exit:** konkrétní tenant funguje, ostatní se nezměnily, rollback ověřen a všechny pending externí kroky výslovně vypsány.

## Testovací a přijímací matice

| Scénář | Nutný důkaz |
|---|---|
| Existující účet + první Google login | Jednorázový account proof, stejné UUID, stejné tickety a role; příště bez hesla. |
| Google email stejný ve dvou organizacích | Dvě oddělené vazby; přihlášení v jedné nikdy nedá session druhé. |
| Sdílená schránka / +N | Žádné automatické propojení aliasů ani doručovací adresy; explicitní důkaz cílového účtu. |
| Nový uživatel | Povoleno jen serverovou registrační politikou; jediný profile/unit; souhlasy, žádné libovolné event membership. |
| Útočník / nevalidní provider důkaz | Špatný issuer/aud/nonce, expirovaný token, replay, podvržený tenant, direct RPC a redirect odmítnuty. |
| Cancel, více tabů, dvojí callback | Žádný nechtěný link, duplicate side effect nebo zablokované tlačítko; safe retry. |
| Timeout během mintu | Stejný kód nepoužit znovu, další nový login funguje, vzniklá vazba nezdvojena. |
| Offline / výpadek | Nová identita nezpřístupní cache před online potvrzením; dosavadní offline režim není plošně zrušen. |
| Smazání/ban/unlink | Žádná session pro smazaný/banned účet, link deletion/alternativní login pravidla vynucena. |
| Web -> Flutter -> restart | Jedna správná session, správný tenant a privátní cache, funkční refresh/logout. |
| Vzhled | Light/dark a šířky 360/390/768/1440; loading, error, link, profile; žádný overflow, čitelný focus a klávesnice. |

Po každé souvislé vlně spustit její cílené testy; ne opakovaně celý test_all po každém editování. Použitelné příkazy:

- `node --test web_client/tests/components/login_modal.test.js web_client/tests/core/auth_bridge.test.js` plus nové testy callback/auth state.
- `fvm flutter test test/startup/router_service_post_login_test.dart test/components/users/login_feedback_test.dart` plus nové flow testy.
- `fvm dart analyze <změněné Dart soubory>`.
- `DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' node web_client/scripts/run_db_tests.js database/tests/google_auth_test.sql` po přípravě izolované DB podle CONTRIBUTING.
- `deno test --allow-env --allow-net --allow-read <nové a změněné Edge testy>`; sítě v unit testech stubovat, skutečný OIDC pouze označená integrační část.
- `node automation/hetzner-supabase/merge/edge-function-test-coverage.mjs` pro coverage/runtime registraci.

Při prvním plánování testy neběžely. Při tomto zpřesnění proběhl níže popsaný izolovaný GoTrue proof; aplikace se neimplementovala. Finální Google OAuth, SDK chování a celý aplikační RLS kontrakt vyžadují další izolovaný integrační průchod.

## Lokální důkaz Supabase z tohoto zpřesnění

Skutečný Docker GoTrue `supabase/gotrue:v2.189.0` a samostatný PostgreSQL `15.8.1.085`, pouze syntetické adresy `example.com`. Auth naslouchal na `127.0.0.1:55989`, DB nebyla publikována. Použil se nezměněný aktuální `create_user_in_organization_with_data_pure.sql` a minimální tabulka `user_info`, bez kopírování produkčních dat. Google provider nebyl zapnut a žádný email se neodeslal. Dočasné kontejnery, volumes a síť byly po důkazu odstraněny; existující lokální DB na 55432 se neměnila.

Výstupy bez tokenů: [prefix proof](google-sign-in-reference-2026-10-01/supabase-prefix-proof.json), [existing-user proof](google-sign-in-reference-2026-10-01/supabase-existing-user-proof.json).

| Ověření | Skutečný výsledek |
|---|---|
| `1+planner@example.com`, `2+planner@example.com` | Každý má vlastní UUID; generate/verify zachovaly správné UUID a email |
| `1+planner+1@example.com` | Plus alias zachován, správný samostatný účet |
| `1+1+real@example.com` | Skutečný raw email začínající číslem+ nebyl chybně zbaven části adresy |
| Refresh a původní password login pro 4 identity | Vše prošlo, žádná změna původního UUID/hesla |
| Password login bez org prefixu | Odmítnut |
| Opakování spotřebovaného OTP | Odmítnuto |
| Magiclink pro chybějící účet při disable_signup=true | HTTP 200, vznikl nový Auth user: tento mechanismus nelze použít bez změny |
| Dva magiclinky pro stejného uživatele | První verify 403, druhý 200: nutný společný per-user issuer/lease |
| Recovery proof pro chybějící účet | HTTP 404, žádný nový účet |
| Recovery proof pro existující účet | HTTP 200, stejné UUID, úspěšný refresh, nezměněný password hash, AAL1/OTP |
| Banned účet | Redeem odmítnut HTTP 403 |

Důkaz potvrzuje technickou kompatibilitu prefixed emailů a standardní Supabase session. Není to důkaz hotového Google loginu, registration unit transakce, produkční konfigurace, RLS/permissions, mobilních callbacků nebo distribučně správného lease. Lokální image tag měl stažený digest `sha256:385184459f57569c54c25209f51f3b2be99ddd7c4ce9e3555b5d3eea8447b7cf`; repo runtime pin uvádí jiný digest. Shodná hlášená verze v2.189.0 nenahrazuje release ověření přesného nasazovaného obrazu.

Ve vlně 1 převést důkaz do reprodukovatelného isolated integračního testu s fixture setupem/cleanupem; teprve potom jej rozšířit o broker. Povinně přidat souběh Google/QR/cancel, user deletion mezi resolve a mint, prodlouženou HTTP odpověď po lease expiry, existující Auth orphan, email mismatch a null registrační flag. Dále ověřit refresh revocation/logout (v tomto lokálním proof nebyly provedeny) a client `setSession`, aby interní recovery proof neotevřel reset hesla.

## Zachované a odstraněné hranice

| Artefakt | Výsledek |
|---|---|
| Password, QR/manual login, reset hesla | Zachovat veřejné kontrakty; QR a cancel-reception převést na společný existing-user issuer a regresně ověřit. |
| Přímé magiclink minty v QR/cancel-reception | Nahradit existující-user recovery issuerem s per-user lease; hledání generateLink prokáže jediného vlastníka v dotčeném scope. |
| Organizací prefixované Auth emaily a user UUID | Zachovat; žádná hromadná migrace. |
| Auth bridge | Zachovat pro současné volající; Google používá vlastní bezpečný callback bez session v URL. |
| Dočasný spike, duplicitní callback/finalizer | Odstranit před handoff; jediná kanonická cesta Google flow. |
| Staré texty „jediný anonymní endpoint“ | Aktualizovat s přesnými novými proof boundaries. |
| Expired attempts | Kontrola TTL synchronně + explicitní úklid jobem. |
| Tenant Google capability | Trvalá serverová policy; ne dočasný rollout flag bez vlastníka. |

## Neověřené předpoklady, externí kroky a rollback

- Google Cloud projekt/client, consent publishing a secret nejsou ověřené. Vlastník nasazení je musí dodat/nakonfigurovat; lokální implementaci a mock testy to neblokuje, živý E2E ano.
- Přesná produkční overlay větev, activation a runtime flags nebyly v této plánovací session provozně ověřeny. Release autor je vyřeší podle pravidel před jakýmkoliv zápisem. `main` má prázdné activation hodnoty a není hotový release manifest.
- Google přihlášení v Mendeliu bylo vizuálně potvrzeno, jeho serverová implementace a skutečný login nebyly prozkoumány. Neukládat odhady o frameworku/provideru jako fakta.
- Mobilní verified links a iOS 4.8 jsou předem známé release dependencies, nikoli detaily odložitelné po vydání.
- Broker přidává nový bezpečnostní povrch. Session mint/prefix mají lokální důkaz, anti-CSRF, SDK eventy, MFA a callback/retry kontrakt se musí ověřit ve fázi 1. Tag v2.189.0 nebyl totožností digestu potvrzen proti produkčnímu obrazu.

Rollback: vypnout serverovou Google capability a vydávání nových pokusů pro vybraný tenant, skrýt CTA, ponechat standardní session/heslo/QR a existující data/linky. Účty vytvořené Google musí mít funkční cestu obnovy hesla. Nevracet schema destruktivně, nemazat nově vzniklé účty a nepřepínat provoz na starý cloud. Rozpracované pokusy invalidovat; již vydané sessions případně revokovat samostatným explicitním provozním rozhodnutím.

## Definice hotovo

- Google přihlášení/propojení/registrace fungují přes jeden backend owner a zachovávají tenantovou izolaci i uživatelské UUID.
- Web i Flutter dodržují vizuální brief; všechny zásadní stavy jsou doložené screenshoty a funkčními testy.
- Backend, migrace, runtime policy, coverage i provozní dokumentace jsou konzistentní; není nezdokumentovaný anonymní bypass.
- Password/QR/recovery, synchronizace, refresh a logout nadále fungují.
- Provozní připravenost každé platformy je explicitní; blokovaný iOS nebo chybějící credentials nejsou vykázány jako úspěšný rollout.
- Handoff uvádí změněné soubory, výsledky testů, screenshoty a přesný seznam neprovedených externích kroků.

## Externí zdroje

Ověřeno 2026-10-01. Tyto zdroje dokládají provider protokol a provozní omezení, nikoli navržený FestApp broker:

- [Google OpenID Connect](https://developers.google.com/identity/openid-connect/openid-connect): code flow, state/nonce, token validation a stabilní sub.
- [Google branding](https://developers.google.com/identity/branding-guidelines): vzhled provider tlačítka.
- [Supabase Google login](https://supabase.com/docs/guides/auth/social-login/auth-google): standardní varianta pro srovnání.
- [Supabase identity linking](https://supabase.com/docs/guides/auth/auth-identity-linking): standardní linking, odlišný od současných prefixed tenantových účtů.
- [Self-hosted OAuth](https://supabase.com/docs/guides/self-hosting/self-hosted-oauth): GoTrue provider konfigurace a callback; není návod zapnout paralelní cestu vedle brokeru.
- [Apple App Review Guidelines 4.8](https://developer.apple.com/app-store/review/guidelines/#login-services): release podmínka sociálního loginu na iOS.

Doplňující zdroje pro zpřesněnou Supabase hranici:

- [GoTrue v2.189.0 adminGenerateLink](https://github.com/supabase/auth/blob/v2.189.0/internal/api/mail.go): magiclink při absenci uživatele přejde na signup, recovery vrací not-found; oba existujícímu účtu zapisují recovery slot.
- [GoTrue v2.189.0 verify](https://github.com/supabase/auth/blob/v2.189.0/internal/api/verify.go): ověření OTP a banned účtů.
- [Google backend validation](https://developers.google.com/identity/sign-in/web/backend-auth): stabilní sub, validace issuer/audience a rozdíl Gmail/Workspace proti externím emailovým adresám.
- [Supabase generateLink](https://supabase.com/docs/reference/javascript/auth-admin-generatelink) a [verifyOtp](https://supabase.com/docs/reference/javascript/auth-verifyotp): serverová API hranice pro získání standardní session.
