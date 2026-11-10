# Proveďte sjednocení správy členství a pozvánek

Pracujte v `/Users/miakh/source/festapp`. Přečtěte platné AGENTS.md, CLAUDE.md,
`docs/architecture/ai_context.md` a celý autoritativní plán:

`docs/plans/access-membership-invitations-plan-2026-11-10.md`

Implementujte celý plán včetně oddílů „Hranice, které sjednocení nesmí změnit“,
„Zpřesnění kontraktu po hlubší kontrole“ a „Efektivní provádění a pořadí důkazů“.
Cíl: jeden doménový owner a konzistentní uživatelský tok pro přidání členů,
scoped role, pozvání, doručení, přijetí a odvolání v unit, occasion a setupu.
Členství, oprávnění, doručení a přijetí zůstávají odlišné skutečnosti.

Závazně zachovejte:

- Pozvánky běžným uživatelům Festapp s vygenerovaným/nastaveným heslem, včetně
  oprávněného nastavení hesla existujícímu běžnému účtu. `participant_credentials`
  a SIGN_IN_CODE nejsou obsolete. Heslo nezaměňujte s expirovaným OTP; ověřte
  skutečný login a stávající životnost obou mechanismů.
- Týmová pozvánka/notice nemění heslo existujícího účtu. Záměr musí ověřit server;
  unit scope nerozšiřuje oprávnění k nastavování hesel.
- Resend/notification-only nemění profil ani role. Odvolaná práva se nesmějí
  obnovit starým pending invite. Nezměňte hierarchii auth policy ani scope role.
- Existující přihlášky, automatická potvrzení, objednávky a platby. Selhání
  volitelné pozvánky je nesmí vracet zpět ani nově vyžadovat ruční potvrzení.
- Staré platné odkazy, audit a skutečné evidence odeslání bez nového rozesílání,
  přidělování práv nebo vytváření účtů jako vedlejšího účinku migrace.

Postupujte autonomně až k hotové lokální implementaci, ne pouze k dalšímu plánu.
Použijte verification: standard. Nejprve zachyťte aktuální branch/HEAD a cizí
rozpracované změny; nepřepisujte je ani nepřidávejte nesouvisející migrace. V první
vlně reprodukujte organizační přidávání nebo přesně ponechte historickou příčinu
nepotvrzenou. Omezte další průzkum na konkrétní neznámé a skutečné callery.

Pracujte po koherentních řezech dle plánu. Reuse identity/receipt/queue/template/
sync owners; nevytvářejte obecný workflow framework ani druhou business cestu.
Transakční oprávnění ověřujte i při replay; service_role nesmí obejít auth.uid()
policy. Command ID/intent hash jsou stabilní; ciphertext ani token nejsou request
identity. Doména a požadovaný enqueue jsou atomické v hranicích stanovených plánem.

Ověřujte cílenými contract batches, skutečný login, migraci a souběhy na
samostatných DB connections. Browser až po stabilním API, na disposable lokálním
prostředí se stubbed providerem. Dodržte jeden Flutter task a --concurrency=1.
Nespouštějte plošné buildy po každém editu ani opakovaně passing checks. Na konci
uzavřete deletion ledger a proveďte odpovídající canonical CI mirror lanes dle
repo pravidel. Nezahajujte nezávislý subagent audit; browser delegujte dle AGENTS.md.

Každý starý veřejný RPC/endpoint/odkaz buď bezpečně migrujte, nebo ponechte jen
autorizovaný mechanický adaptér s konkrétním spotřebitelem a podmínkou odstranění.
Zahrňte přímý `add_user_to_unit`, worker validity/admission, šablony, stavové
projekce, runtime registrace, source manifests, Client Sync, testy i dokumentaci.
Nenechávejte placeholdery, spekulativní fallbacky ani duplikovaná doménová pravidla.
Když aktuální důkaz vyvrátí předpoklad, opravte přímo autoritativní plán a
pokračujte k témuž výsledku; nevydávejte nepotvrzenou historickou příčinu za opravenou.

Tento prompt autorizuje lokální implementaci a lokální ověření po jeho zadání.
Bez dalšího zadání neprovádějte commit, push, produkční migraci, deploy, změny
zákaznických rolí ani rozesílání skutečných e-mailů. Neobcházejte publish/release
gates. V závěru stručně uveďte výsledek, testy, odstraněné cesty, ponechané vnější
adaptéry a přesný rozdíl mezi lokálně hotovým a dosud nenasazeným stavem.
