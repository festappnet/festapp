# Implementace osobního přehledu objednávky

Pracuj v `/Users/miakh/source/festapp`. Přečti AGENTS.md, CLAUDE.md,
docs/architecture/ai_context.md a celý autoritativní
[follow-up plán](order-overview-waitlist-follow-up-plan-2026-10-13.md).
Přečti také původní plán kapacity a aktuální implementační evidenci uvedené v něm.

Původní vlny 1-6 jsou podle lokální evidence implementované a ověřené, produkční
rollout neproběhl. Ověř aktuální kontrakty, neimplementuj je znovu. Implementuj opakovaně dostupný osobní
přehled čekání, nabídek, vzniklých objednávek, evidované úhrady a stavu jednotlivých
vstupenek v JS i Flutter. Přijetí/odmítnutí používá původní formulář a write scope.
Samostatný view token dává pouze čtení přes minimální SQL DTO, včetně bezpečně
ověřených partial children a in-place conversion. Storno zákazníkem je mimo rozsah.
Sekce plánu určují konkrétní současné obrazovky, DTO, payment/ticket mapping,
samostatný fragment, encrypted source lifecycle a bezpečný bootstrap z aktivních
offer/manage odkazů. Order.state=paid není důkaz plné úhrady; delivery_receipt
není trvalý přístup. Zachovej terminal bezpečnost starých nabídek, původní success
QR a acceptance i při selhání doplňkového přehledu. Backendový read nevydává write scope.

Verification **standard**, cílené kontroly dle plánu. Zachovej cizí rozpracované
změny, před editací čti diff. Pokud se výchozí evidence změnila, aktualizuj plán
a dotčenou vlnu. Žádné placeholdery, kopie platební logiky, širší offer tokeny,
přímé e-maily nebo neplánované fallbacky. Nezahajuj nezávislý audit ani subagenty
bez výslovného zadání. Hotovo prokazují SQL bezpečnostní/platební matice a testy
obou UI, včetně návratu, partial přijetí a opakovaného otevření.

Toto je zadání budoucí realizace, ne pokyn k implementaci při přípravě plánu.
Commit, push, produkční migrace, deploy a tenant rollout vyžadují samostatnou
autorizaci. Při předání uveď výsledek, ověření a přesný zbývající krok či blocker.
