# Implementace zákaznické samoobsluhy

Pracuj v `/Users/miakh/source/festapp`. Nejdříve přečti platné `AGENTS.md`,
`CLAUDE.md`, `docs/architecture/ai_context.md` a celý autoritativní plán:

`docs/plans/customer-self-service-plan-2026-11-15.md`

Cíl: zákazník upravuje povolené údaje, stornuje objednávku, sleduje refundaci
a přesune podporovaný termín podle explicitní policy pořadatele. Rozšiř existující
přehled objednávky ve webu a Flutteru. Pro nepodporovanou automatiku musí vzniknout
viditelný požadavek obsluze, nikoli falešně potvrzená změna.
Hlavní vstup je stávající tlačítko z e-mailu. U něj přidej kontextový text o
dostupných změnách přes společný email presenter, zachovej URL a jedno tlačítko.
Součástí implementace je aktualizace uživatelské CZ/EN nápovědy v
automation/release/help/: zapnutí feature a operací, cesta z e-mailu,
potvrzování změn, storno, přesuny, stav refundace a požadavky obsluze.
Aktualizuj návody, navigaci a vyhledávání; ověř odkazy, omezení a shodu
se skutečným UI. Nové screenshoty musí mít light mode a UI i příklady
v jazyce návodu. Bez aktualizované nápovědy není implementace hotová.
Samoobsluha je extra occasion feature `customer_self_service`, ve výchozím stavu
vypnutá. Zapnutí samo nepovoluje jednotlivé operace. Server vynucuje feature
i dílčí policy a vypnutí zachovává již přijaté finanční závazky a jejich recovery.

Postupuj po etapách v režimu `verification: standard`. Zachovej oddělené
zákaznické oprávnění, čtecí capability a RBAC obsluhy. Sdílej doménové efekty,
platební/refundovací engine, e-mailovou frontu, kapacity a ticket identity.
Nepoužívej service role jako náhradu nároku, nepřidávej fallbacky ani druhý ledger.
Respektuj konkrétní omezení přesunů, faktur, slev a čekací listiny v plánu.

Aktuálním důkazem vyvrácené předpoklady oprav v autoritativním plánu a adaptuj
dotčenou etapu. Hotovo vyžaduje kontrakty autorizace, souběhu a retry, ověření
finančních faktů a odstranění dočasných bypassů. Flutter spouštěj jen jeden
workstation task a testy s `--concurrency=1`.

Bez další autorizace neprováděj commit, push, produkční migraci, release ani
zapnutí samoobsluhy. Při předání odděl implementované chování od nenasazených
operací a uveď přesné hranice automatických a ručních změn.
