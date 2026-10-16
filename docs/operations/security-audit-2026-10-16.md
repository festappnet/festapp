# Audit zabezpečení a provozních limitů serveru Festapp

Datum: 2026-10-16. Audit běžícího serveru, pouze čtení. Nebyly změněny produkční údaje, oprávnění, konfigurace ani služby. Nebyl proveden zátěžový test, obnova zálohy ani spuštěna nebezpečná zapisovací funkce.

## Následná náprava 2026-10-16

Tento audit zachovává původní nálezy jako historický snapshot. Následně nasazené migrace `20261016170000/171000/172000` odstranily čtyři nebezpečné/nepoužívané funkce, uzavřely interní sync a opravily ACL/search_path. Caddy cap i existující monitor jsou aktualizované a skutečný backup prošel izolovanou obnovou. Aktuální důkazy a dosud otevřené provozní body C vlastní [produkční receipt](security-remediation-20261016/production-result.json) a [aktuální serverový plán](../plans/server-security-remediation-plan-2026-10-16.md). Původní závěr níže nepopisuje výsledný katalog po opravách.

## Závěr

**Nasazený backend nelze považovat za dostatečně zabezpečený. Nejvyšší prioritu mají veřejně spustitelné privilegované RPC bez autorizace.** Izolace administrace a databáze od veřejných portů funguje při provedených kontrolách, ale neřeší chyby uvnitř veřejného API. Další významná rizika jsou nesprávné synchronizační RLS politiky, rozdíl konfigurace mezi repozitářem a serverem a chybějící limity prostředků kontejnerů.

Nejde o důkaz napadení. Audit nezkoumal kompletní historii přístupů a nedokládá, zda někdo chyby již zneužil.

## Ověřený cíl a metoda

- Tenant `festapp`, organizace 1, `prod/festapp:automation/project.conf`.
- `https://live.festapp.net/backend-activation.json`: tenant `festapp`, generation 1, backend `canonical`.
- API `https://api.festapp.net`; SSH hostname a aktivní databáze odpovídají chráněným lokálním target assertions. Navzdory historickému označení rehearsal jde o aktivní produkční backend.
- SQL běželo v explicitních transakcích `BEGIN READ ONLY`. Kontroly rolí používaly `SET LOCAL ROLE anon` a vracely pouze metadata nebo booleovské informace o viditelnosti.
- HTTP kontroly používaly veřejný anon klíč, bez přihlášení konkrétního uživatele. Výpis tabulek byl omezen `limit=0`. Storage list je čtecí operace přes POST; nebyly vypisovány názvy souborů ani stažen jejich obsah.
- Dosažitelnost nebezpečného RPC byla ověřena neplatným číselným argumentem, který PostgreSQL odmítne při převodu typu před vstupem do těla funkce.

## Potvrzené nálezy

### 1. Kritické: veřejný migrátor může měnit identity všech uživatelů

`public.migrate_users_to_org(bigint)` má anonymní EXECUTE, běží jako SECURITY DEFINER s vlastníkem `postgres` a nemá kontrolu identity ani oprávnění volajícího. Kontroluje pouze, zda parametr není NULL. Následně prochází všechny emailové identity v `auth.identities` a všechny uživatele v `auth.users` a přepisuje jejich emaily přidáním prefixu organizace. Neomezuje změny na zadanou organizaci.

Katalog potvrzuje, že vlastník má UPDATE na obou auth tabulkách. Veřejné API se správným veřejným anon klíčem a neplatným argumentem vrací HTTP 400 / SQLSTATE `22P02`, tedy požadavek dosáhne databázové cesty RPC. Destruktivní volání nebylo provedeno. Dopadem může být hromadné narušení přihlašování a obnovy účtů napříč tenanty; nejde o prokázané převzetí účtu.

Náprava: odebrat EXECUTE od PUBLIC, anon i authenticated; historickou jednorázovou funkci přednostně odstranit po kontrole referencí. Samotné odebrání grantu od anon nestačí, pokud oprávnění stále dědí z PUBLIC.

### 2. Vysoké: neautorizované změny míst a alokací

`public.update_spot(jsonb)` a `public.apply_allocations_claim_only(bigint)` mají anonymní EXECUTE a SECURITY DEFINER. Kontrola celého těla nepotvrdila autorizaci volajícího.

- `update_spot` podle ID mění název, stav, inventory context, resource a resource slot. Místo kontroly obsahuje komentář, že oprávnění teprve mají být doplněna.
- `apply_allocations_claim_only` podle ID objednávky přiděluje dosud volná místa položkám objednávky a mění jejich stav. Kontroluje existenci objednávky a storno, nikoli oprávnění aktéra.

Dopad je neoprávněná změna inventáře/rezervací. Provedení zápisu na produkci se netestovalo. Náprava musí rozlišit interní helper a veřejnou fasádu: internímu helperu odebrat veřejné granty, u klientské operace kontrolovat oprávnění k odvozené akci před zápisem a zachovat legitimní rezervace zákazníků.

### 3. Vysoké: synchronizační tabulky dovolují anonymní zápisy

`public.external_sync_sources`, `public.external_sync_maps` a `public.external_occasions_cache` mají RLS politiku `Allow service role full access`, ale skutečná role politiky je PUBLIC, příkaz ALL a podmínky USING i WITH CHECK jsou `true`. Anon i authenticated mají tabulkové granty pro čtení a zápisy.

Čtecí HTTP požadavky s `limit=0` prošly pro všechny tři tabulky stavem 200. Pod rolí anon byl potvrzen viditelný obsah cache; sources a maps byly při kontrole prázdné. Zápis nebyl proveden. Politika dovoluje vytvářet a měnit konfiguraci/mapování i obsah cache; další dopady závisí na aktivních čtenářích synchronizace a nebyly exploitovány.

Náprava: omezit politiky na service_role a odebrat klientské tabulkové granty, pokud nejsou potřeba. Předem zmapovat legitimní čtenáře, nikoli zachovat veřejný zápis kvůli čtení.

### 4. Vysoké provozní riziko: ochrany v repozitáři nejsou nasazené

Živý `/opt/festapp-supabase/docker/caddy/Caddyfile` proti současnému pracovnímu souboru `automation/hetzner-supabase/runtime/Caddyfile` postrádá explicitní omezení původu na Cloudflare/loopback, limity těla 64 KB pro Auth a 32 MB pro API, timeouty příjmu a přepis důvěryhodných IP hlaviček. Živý Auth kontejner nemá nastavený `GOTRUE_RATE_LIMIT_HEADER`; pracovní Compose jej již definuje. Pracovní soubory obsahují necommitnuté změny a nejsou samy o sobě důkazem schválené verze k nasazení.

V Envoy nebyl v kontrolovaných konfiguračních souborech nalezen filtr rate limitu. Existují timeouty tras 30 s a buffer 32 KiB na spojení, což není limit počtu požadavků. Cloudflare WAF/rate-limit pravidla nebyla dostupná k ověření. Nelze tedy tvrdit, že veřejné API nemá žádnou ochranu proti zahlcení, ani že má ověřený celkový limit.

Přímé připojení na origin z této stanice timeoutovalo včetně portu 443. Obejití Cloudflare proto nebylo prokázáno. Pravidla firewallu poskytovatele nebyla načtena. Lokální UFW je neaktivní a nftables nemá zjištěnou hostitelskou INPUT allowlist politiku, pouze pravidla související s Dockerem. SSH naslouchá na všech rozhraních, ale test veřejného portu 22 timeoutoval.

Náprava: ověřit pravidla poskytovatele a Cloudflare, připravit schválenou konfiguraci a nasadit obranu i na originu. Při zavádění firewallu zachovat funkční chráněný SSH tunel a nouzový přístup.

### 5. Vysoké provozní riziko: kontejnery nemají limity prostředků

Všech 13 běžících kontejnerů má Docker Memory=0, NanoCpus=0 a PidsLimit=null, tedy nejsou nastavené individuální limity RAM, CPU ani procesů. Host má přibližně 3,7 GiB RAM, bez swapu; v okamžiku měření bylo k dispozici asi 825 MiB. Edge runtime spotřebovával asi 780 MiB. Jedna služba může vyčerpat prostředky společné databázi a Auth. Význam nulových limitů odpovídá [dokumentaci Dockeru](https://docs.docker.com/engine/containers/resource_constraints/).

Živý router Edge Functions má limit jednoho workeru 512 MB a timeout 7 minut. To není souhrnný limit kontejneru. Explicitní CPU soft/hard limit 20/30 s je v routeru doplněn pro emailový worker.

Náprava: stanovit rozpočty podle skutečné spotřeby, ponechat rezervu OS a databázi, zavést limity souběhu veřejných operací a zvážit navýšení RAM. Nastavení příliš nízkých limitů bez měření může samo vyvolat výpadky. V kontrolovaném kernel logu za 14 dní nebyly nalezeny OOM události.

### 6. Střední: neúplná hygiena privilegovaných funkcí a grantů

Ve `public` je 635 SECURITY DEFINER funkcí, z nich 224 spustitelných rolí anon a 423 rolí authenticated. Počet sám o sobě není zranitelnost. U 88 ale chybí explicitní `search_path`, z nich 84 má anonymní EXECUTE. Public/eshop/extensions schémata neumožňují anon ani authenticated CREATE, což omezuje některé scénáře zneužití; eskalace přes search_path nebyla prokázána.

Na 61 tabulkách public/eshop má anon právo TRUNCATE. PostgreSQL jej [nepodřizuje RLS](https://www.postgresql.org/docs/17/ddl-rowsecurity.html). Nebyla nalezena ani ověřena veřejná HTTP cesta, která by samotný TRUNCATE vykonala; jde o zbytečné oprávnění a zesílení dopadu jiné chyby, nikoli důkaz přímého mazání přes REST.

Veřejně spustitelné jsou také dblink funkce v public. Síťová volání ani přístup do jiných databází se netestovaly. Je vhodné omezit rozšíření a interní helpery na skutečně potřebné role.

Historická SECURITY DEFINER funkce `send_email_mailersend` má anonymní EXECUTE a posílá přímo mimo současnou frontu. Klíč `MAILERSEND_API_TOKEN` ale v tabulce private_keys při kontrole nebyl nakonfigurovaný, takže funkční zneužití odesílání není doloženo. Odstranit mrtvou veřejnou cestu a nezavádět do ní znovu token.

### 7. Střední: ledger neprokazuje aktuální bezpečnostní konfiguraci

Ledger obsahuje migraci `20260218120000_fix_all_security_lints.sql`, jejíž repozitářová verze omezuje tři synchronizační politiky na service_role a nastavuje search_path migrátoru. Živý katalog přesto obsahuje PUBLIC politiky a migrátor bez search_path. Příčina rozdílu nebyla určena; nelze z tohoto samotného usuzovat na chybu konkrétního deploye.

Naopak migrace `20261009120000` je v ledgeru a kontrolované scan/attendance funkce dnes obsahují NULL-safe porovnání a kontroly identity. Starý audit z 2026-10-09 proto nelze celý vydávat za aktuální stav produkce.

Náprava: kontrolovat po deployi skutečné definice, granty a politiky, nejen seznam migračních verzí; doplnit detekci driftu.

### 8. Střední: denní záloha bez potvrzeného PITR a čekající restart

Poslední plánovaná záloha doběhla 2026-10-16 v 02:39:51 UTC. Receipt potvrzuje šifrování, nevytváření plaintext artefaktů a ověření uploadu mimo server do R2. Retence je 14 dní plus čtyři týdenní kopie. Obsahuje dump DB, globals, storage a runtime. Backup i upload provozních logů mají systemd Result=success.

PostgreSQL má archive_mode=off; nepřetržité WAL/PITR zálohování nebylo doloženo. Denní timer při úspěšném pravidelném běhu znamená možnou ztrátu změn od poslední zálohy, řádově až jeden den. Při neúspěšných bězích i více. Nejnovější nalezené názvy restore-drill adresářů jsou z 2026-09-10; jejich úplný výsledek ani nová obnova se v tomto auditu neověřovaly. Více artefaktů v online sadě není samo o sobě důkaz atomického snapshotu všech služeb.

Host hlásí požadovaný restart po aktualizacích kernelu/libc; má uptime přibližně 49 dní. Dostupné jsou také aktualizace Docker/containerd. Audit neprovedl CVE scan a neoznačuje konkrétní nainstalovaný image za prokázaně zranitelný. Naplánovat údržbu, ověření obnovy a stanovit přijatelnou ztrátu dat i dobu obnovy.

## Skutečně zjištěné limity

| Oblast | Nasazená hodnota | Výklad |
| --- | --- | --- |
| PostgreSQL spojení | 100, z toho 3 rezervovaná pro superuser | Při kontrole asi 26 backend procesů v pg_stat_activity; nejde o počet podporovaných uživatelů |
| SQL statement_timeout | anon 3 s, authenticated 8 s, authenticator 8 s | Globální default je 0; neplatí univerzálně pro interní/admin operace |
| SQL lock timeout | authenticator 8 s | Globální default 0 |
| Idle transaction timeout | globálně 0, auth admin 60 s | Ne všechny role mají ochranu před otevřenou nečinnou transakcí |
| REST max rows | 1000 | Není to obecný limit počtu položek uvnitř JSON vráceného RPC |
| Storage upload | 50 MiB v Storage API | ticket-fonts má vlastní limit 8 MiB; v živém Caddy nebyl nalezen nižší explicitní body limit |
| Edge worker | 512 MB, 7 minut | Souhrnný kontejner je bez RAM limitu |
| Email přidělená kapacita | 2 zprávy/s, 10 000/24 h | Sdílený provider účet má 14/s a 50 000/24 h; platí centrální gate, bezpečnostní rezerva a souběh |
| Email souběh | max_preparing=2, max_sending=2 | paused=false, čerstvá kvóta i heartbeat, circuit_until=null |
| Logy Docker | 20 MB x 3 soubory na kontejner | Upload mimo host byl úspěšný |
| Disk | 38 GB, využito 61 %, asi 15 GB volných | Okamžitý stav, nikoli predikce růstu |

Auth nemá explicitně nastavené vlastní proměnné rate limitů, minima hesla, CAPTCHA ani refresh-token rotace. To **neznamená, že jsou všechny tyto ochrany vypnuté**: část nastavení má defaulty konkrétního GoTrue buildu. Přesné efektivní hodnoty a funkční rozlišení klientských IP nebyly ověřeny. Vlastní IP hlavička v nasazeném Auth chybí; [dokumentace Auth](https://supabase.github.io/auth/) vyžaduje důvěryhodný upstream při jejím použití. Neposílal se hromadný login provoz k vyčerpání limitů. V DB existují samostatné tabulky pro limity resetu hesla, externího loginu a reception; jejich existence sama nepotvrzuje pokrytí všech endpointů.

## Ochrany, které audit potvrdil

- Veřejná administrace vrací 302 na Cloudflare Access, veřejné API root i `/pg/` vracejí 404. Přesná identitní/MFA pravidla Access nebyla z control plane načtena.
- Gateway publikuje pouze loopback 8000/8443, admin listener je na loopback 8999. DB, pooler, Studio a meta nemají veřejně publikované Docker porty.
- SSH nepřijímá hesla ani keyboard-interactive, root pouze přes klíč. Tajné runtime soubory mají root:root a mód 0600.
- Všech 32 eshop tabulek a 10 storage tabulek má RLS; public 101 ze 103. Dvě bez RLS nemají zjištěný klientský přístup. Žádná z kontrolovaných tabulek bez RLS neměla klientské CRUD granty.
- Storage má jedinou politiku `ticket_fonts_private`, a ta je RESTRICTIVE. Bez permissive politiky klientské role nedostanou přístup k řádkům. Samotné široké tabulkové granty tedy neprokazují anonymní přístup k souborům. List privátních bucketů nevrátil položky; nebyl prokázán únik ani možnost zápisu souboru.
- Všechny kontejnery byly při kontrole spuštěné; služby s healthcheckem healthy, žádný privileged kontejner ani mount docker.sock. Caddy a cloudflared mají read-only root filesystem.
- Globální router Edge Functions má VERIFY_JWT=false; kontrolované funkce proto používají vlastní autorizaci. Email worker a send-tickets volají authorizeRequest, bank-sync-manage ověřuje uživatele i právo k účtu, bankovní webhook používá podpis z raw těla. Vypnutý globální JWT check sám o sobě není nález neautorizovaného přístupu ke všem funkcím.
- Pgaudit je zapnutý pro zápisy/DDL/role u postgres a authenticator; audit log_statement je vypnutý, což omezuje ukládání hodnot parametrů. Host monitoring běží každou minutu; doručení skutečného varování nebylo testováno.

## Doporučené pořadí nápravy

1. Bezodkladně připravit a cíleně ověřit odebrání veřejných grantů nebezpečným interním RPC; opravit autorizaci klientských zapisovacích funkcí. Zahrnout negativní scénáře anon, cizí uživatel a cizí tenant i pozitivní případy oprávněných uživatelů.
2. Omezit synchronizační politiky a nepotřebné granty, ověřit jejich skutečný stav po nasazení.
3. Nasadit schválené ochrany proxy/IP hlaviček a doložit pravidla Cloudflare/provider firewallu. Ověřit skutečné Auth i veřejné API limity bez produkčního zátěžového útoku.
4. Zavést rozpočty RAM/souběhu, plán aktualizací a řízeného restartu. Ověřit upozornění při vyčerpání prostředků.
5. Provést izolovaný restore drill, dohodnout RPO/RTO a podle potřeby zavést průběžné WAL zálohy. Dořešit search_path, TRUNCATE a veřejně dostupná rozšíření.

Audit nezahrnuje nasazení oprav. Pro sdílený backend musí náprava zohlednit existující klienty ostatních tenantů; žádné jejich větve ani releasy nebyly měněny.

## Otisky potvrzených živých definic

SHA-256 z `pg_get_functiondef`, nikoli z pracovní kopie zdrojů:

| Funkce | SHA-256 |
| --- | --- |
| migrate_users_to_org | bffc2a764e9306e27dbaf41cfc6a84b3a1b4f05e68a1f6b1363c47934511c973 |
| update_spot | b8f1893387ae5bce92009bc93404fa929495f4a6f511949ee88678a269e7bf8f |
| apply_allocations_claim_only | 82683abace0b696f324a48164a18249d4e0dc7a4f6a45ab714ee4df0174dec7d |
| send_email_mailersend | 0d2b88140ec8e839473c72986761dc38ab054cbb10ad45673cc14f15989b9848 |

## Follow-up implementace - lokální stav 2026-10-16

Tato session nezopakovala audit. Úzký read-only katalog potvrdil původní RPC/sync nálezy a nulové uložené/pg_depend/control-plane cron callery. Opravy jsou lokálně implementované a cíleně ověřené na PG17 v samostatném worktree; nejsou nasazené. Aktuální stav, konkrétní migrační balík a chybějící provozní evidence jsou v [autoritativním plánu](../plans/server-security-remediation-plan-2026-10-16.md#lokální-realizace-2026-10-16---aktuální-stav). Původní produkční nálezy se bez následného live readbacku neuzavírají.
