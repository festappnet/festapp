# Předání do další session: Google přihlášení FestApp

Pracuj v `/Users/miakh/source/festapp`. Implementuj autoritativní plán
`docs/plans/google-sign-in-plan-2026-10-01.md`; před úpravami ho přečti celý spolu s AGENTS.md, CLAUDE.md a docs/architecture/ai_context.md. Verification: standard.

Cíl: kvalitní „Pokračovat s Google“ ve webklientu i Flutteru, bezpečné propojení stávajícího účtu a nová registrace při zachování organizací, UUID, vstupenek a práv. Uživatel výslovně vyžaduje grafickou úroveň webklienta vstupenky.online. Respektuj vizuální brief a reference v `docs/plans/google-sign-in-reference-2026-10-01/`; dodej skutečné screenshoty všech podstatných stavů, light/dark a mobilních rozměrů.

Navazuj na uložený lokální důkaz GoTrue v2.189.0 a doplň zbývající integrační ověření z plánu; sekce D1a-D6 jsou závazné. FestApp používá tenantem prefixované Auth emaily a různá UUID téže osoby v různých organizacích. Prosté `signInWithOAuth` by neřešilo zachování identity. Plán volí Google OIDC broker s ověřeným issuer/sub, explicitním propojením a běžnou Supabase session pro původní účet. Žádné automatické email linking, globální změny UUID, vlastní JWT signer, triggery ani druhá paralelní Google login cesta. Vyvrátí-li spike předpoklad, aktualizuj plán s důkazy před další implementací.

Prefix přidává při tvorbě účtu právě jednou SQL writer: `orgId + '+' + lower(trim(rawSignInEmail))`. Rozlišuj `1+jan@example.com`, `1+jan+1@example.com` a legitimní raw email `1+jan@example.com`, jehož Auth pod org 1 je `1+1+jan@example.com`. Existující účet resolve přes UUID/profile, nikdy mint jen podle emailu z Google. Zachovej skutečný Google token a sub beze změny.

Lokální test prokázal dvě pasti: `generateLink(magiclink)` vytváří chybějící účet i při disable_signup=true a souběžné linky přepisují recovery slot. Plán proto volí interní `generateLink(recovery)` + serverové `verifyOtp(recovery)`, kontrolu UUID před/po mintu a společnou per-user lease. Převést na ni také QR exchange a cancel-reception revokaci; veřejné kontrakty zachovat. Klient dostává pouze session a nesmí vstoupit do reset-password UI. Ověř tuto část na SDK, přesném runtime obrazu a při souběhu/deletion; lokální HTTP proof není hotový E2E.

Postupuj po vlnách plánu. Zachovej cizí rozpracované změny. Použij existující registrační invarianty, session finalizaci, design tokeny, navigaci a překlady. Doplň migrace, RLS/grants, explicitní runtime registraci anonymních proof endpointů, coverage, TTL cleanup a account deletion. Ověř útoky, retry, souběh, tenant isolation a skutečný GoTrue session mint; neomezuj se na UI test nebo mock provideru.

Browser kontroly pouze izolovaně a headless. Na tomto stroji globální `~/.agent-browser/config.json` nastavoval provider Panerelay: použij vlastní explicitní prázdný config a jedinečnou session; nepřipojuj se k uživatelovu Chrome. Neměň reálné účty kvůli vizuální kontrole.

Implementace je pro společný main, první budoucí rollout pro vstupenky.online. Bez samostatného zadání necommituj, nepushuj, nenasazuj migrace/Edge ani neměň Google Console; nevydávej další tenanty. Nepoužívej historické cloudové zdroje. iOS vydání potřebuje vyřešení Apple 4.8, případný Apple provider je samostatný rozsah.

Pokračuj samostatně v dostupné lokální práci i při chybějících credentials. Na konci uveď implementované chování, výsledky cílených testů a vizuálních kontrol, odstraněné dočasné cesty a přesné zbývající externí/release blokery. Neoznačuj neověřený OAuth E2E nebo nevydanou platformu za hotovou. Nezapínej subagenty bez explicitního zadání.
