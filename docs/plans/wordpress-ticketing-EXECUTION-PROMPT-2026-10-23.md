# Implementuj a skutečně ověř WordPress plugin vstupenky.online

Pracuj v `/Users/miakh/source/festapp`. Přečti `AGENTS.md`, `CLAUDE.md`,
`docs/architecture/ai_context.md` a celý autoritativní plán:
`docs/plans/wordpress-ticketing-plan-2026-10-23.md`.

Závazné jsou jeho úvodní části „Závazný rozsah první etapy“ a „Doplnění první
etapy: účty, skutečné ověření a rychlost“. Implementuj **pouze vstupenky.online**.
Festapp Tickets je budoucí samostatný projekt. Nezůstaň u dalšího plánu:
dodej funkční plugin, skutečné testy a balíček připravený pro WordPress.org.
Verification: standard.

## Postup

1. Jednou zjisti relevantní stav checkoutu, kontejnerů, portů a dostupných účtů.
   Zachovej cizí změny. Přečti jen potřebné části existujícího embed kontraktu,
   fixture a vlastníků nákupu. Změněné faktické předpoklady oprav v plánu.
2. Zajisti tři oddělené přístupy: správce vlastního testovacího WordPressu,
   testovací pořadatel služby a vydavatel na WordPress.org. Uživatel autorizoval
   přihlášení ke svému správnému účtu a přípravu/dokončení potřebné registrace
   při potvrzené identitě a emailu. Nezakládej duplicitu a neodhaduj identitu.
   Ověř vlastnictví značky, kontaktní email a stav 2FA; počítej s odděleným SVN
   přístupem pro budoucí vydání. Netvrď, že máš heslo nebo session, dokud je nemáš.
   Při nutném přihlášení, potvrzení emailu či 2FA vyžádej jeden konkrétní krok
   vlastníka, pokračuj v nezávislé práci a nechtěj heslo ve zprávě. Nedostupnost
   WordPress.org neblokuje dokončení lokálního pluginu a ZIP.
3. V `integrations/wordpress/` vytvoř izolované lokální WP přes připnuté wp-env,
   Docker a WP-CLI, seed, README a start/stop. Používej pnpm 11.24.0; první
   vytvoření lockfile a další instalace frozen. Ověř loopback bind, existující
   porty a připni skutečně ověřené WP/PHP verze. Placený WordPress.com není třeba.
4. Implementuj pouze `integrations/wordpress/vstupenky-online/`: Gutenberg blok,
   `[vstupenky_online url="…"]`, společný interní renderer a validaci, automatickou
   i pevnou výšku, přístupný titulek a fallback. Přidej místní administrativní
   nápovědu, český onboarding, překladatelnost a anglické readme pro review.
   Použij existující `/form/<saved-slug>?embed=1` a `/embed.js`. Ověř přesné
   produkční originy vstupenky.online, bezpečně escapuj výstup a odmítej cizí
   originy, osobní fragmenty i nebezpečné URL. Lokální fixture povol jen explicitní
   development konfigurací. Editor nemá načítat vzdálenou administraci.
5. Dokonči a dolož skutečný průchod: přihlášení správce -> instalace finálního ZIP
   -> aktivace -> registrace/přihlášení testovacího pořadatele -> uložený formulář
   -> vložení bloku/shortcode -> publikace -> nákup nepřihlášeným návštěvníkem
   -> uložená objednávka a kapacita -> potvrzení -> PDF/QR -> odbavení.
   Ověř běžnou vstupenku i sedadlo, relevantní opakování a selhání. Použij reálné
   vlastníky služby a disposable backend dle plánu a festapp-local-e2e skillu;
   mock nestačí jako důkaz nákupu. Email ověř přes kanonickou frontu a lokální
   sink/zachycení, ne odesláním zákazníkům. Žádné skutečné platby nebo produkční
   objednávky. Nezaměňuj lokální email důkaz s produkční doručitelností.
6. Nad ucelenou implementací proveď cílené PHP/WP kontroly a přijímací matici
   plánu: bezpečnost vstupů/oprávnění, blok/shortcode, více instancí, mobil,
   klávesnice, minimální i aktuální WP/PHP, klasická/bloková šablona, helper,
   úložiště, lifecycle a instalace ZIP bez checkoutu. Reálný Safari/iOS ověř
   zvlášť; Chromium viewport nepočítej jako Safari. U každé metody platby dolož
   její konkrétní podporovaný průchod, jinak ji neslibuj.
7. Dokonči licenci, readme a externí service/privacy disclosure, changelog,
   kontakty, screenshoty a katalogovou grafiku. Proveď Plugin Check včetně runtime,
   relevantní WP Coding Standards, PHP syntax a čistou instalaci konečného ZIP.
   Zkontroluj obsah balíčku, zdroje/build instrukce, verzi/Stable tag a SHA-256.
   Připrav `integrations/wordpress/READINESS.md` a konkrétní postup podání.

## Rychlost a hranice

- Použij focused-development skill. Jedna zaměřená průzkumná fáze, pak ucelená
  implementace. Neopakuj celé audity, passing checks ani buildy bez změny vstupů.
  Nezávislé levné kontroly seskup; chybu diagnostikuj cíleně. Kritické důkazy
  nevynechávej kvůli rychlosti. Nevytvářej obecný framework ani zbytečné testy.
- Nevytvářej Festapp Tickets, `shared/`, `products/`, build varianty nebo druhý ZIP.
  Žádný WooCommerce, nový checkout, nová platební integrace ani kopie objednávek
  ve WP. Zachovej stávající SQL/RPC, email, kapacitní a platební autority.
- Browser: agent-browser skill, vlastní izolovaná headless session, žádný zásah
  do aktuálních uživatelových oken. Potřebné lidské přihlášení domluv konkrétně.
  Respektuj jediný Flutter task, nebuildi Flutter bez nutnosti a dodrž E2E brány.
- Nevypisuj hesla, tokeny, 2FA recovery kódy nebo osobní capability URL. Neuváděj
  smyšlené kontakty, domény či právní odkazy. Zastavený kritický průchod označ
  BLOCKED; ostatní nezávislé kroky dokonči.
- Přihlášení, příprava účtu a lokální testy jsou autorizované. Veřejné podání,
  zprávy reviewerům, veřejný/placený staging, commit/push, produkční změny a SVN
  publikace vyžadují následnou autoritu nad konkrétním ověřeným výsledkem.
  Pro jejich schválení nejprve připrav vše potřebné; nezastavuj dříve kvůli
  práci, která do této hranice nespadá.

## Hotovo znamená

Funkční český plugin a konečný ZIP s hashem, reprodukovatelné lokální prostředí,
průchod skutečného nákupu a odbavení, přijímací matice s důkazy a ověřený stav
účtů. Každou položku označ PASS / FAIL / BLOCKED / NOT RUN. Kritický chybějící
průchod znamená „nepřipraveno k vydání“, ne hotový produkt. Zaznamenej známé
limity, přesné příkazy a chybějící lidský/external krok. Rozliš připraveno,
odesláno, schváleno a publikováno. Po práci ukonči vlastní sessions a procesy,
předej návod k jejich restartu a aktualizuj plán. Nic nepublikuj automaticky.
