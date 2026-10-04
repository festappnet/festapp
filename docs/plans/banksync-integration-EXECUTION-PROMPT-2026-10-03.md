# Implementovat Festapp integraci do stávajícího BankSync

Pracuj ve Festapp `/Users/miakh/source/festapp`; kanonický BankSync je `/Users/miakh/source/banksync`, jeho stávající Mendelio kompozice `/Users/miakh/source/roman_seznamka/services/banksync`.

Přečti celý autoritativní plán:

`docs/plans/banksync-integration-plan-2026-10-03.md`

Dodrž relevantní AGENTS.md, CLAUDE.md, ai_context a `verification: standard`. Pracovní checkout obsahuje cizí rozepsané změny; nepublikuj je. Autoritativní sdílené změny patří na main. Nespouštěj samostatný subagent audit bez požadavku.

Cíl: stejný BankSync Worker/D1/fronty/proxy jako Mendelio, nový izolovaný consumer Festapp, jeden automatický bankovní owner a bezeztrátový ledger přes existující Festapp SQL matcher. **Priorita je nejrychlejší bezpečný M1:** scoped Fio API cutover. Implementuj kritický balík souvisle a validuj společně; neblokuj ho obecnými dashboardy, nepodporovanými bankami nebo přestavbou emailového systému. **Migrují se jen Fio tokeny, žádné staré aktivní emaily/adresy. Nové emailové napojení je však povinná součást tohoto zadání** se správnou autentizací/identitou/recovery a ověřeným bankovním emailem; dokonči ho v M2, neodkládej jako volitelnou práci. Pevné čekání 48 h není gate; rozhodují výsledky popsané v plánu. Potom dokonči M2 a deletion ledger v autorizovaném scope.

Nejprve oprav prokázané BankSync mezery: fuzzy drop skutečné druhé platby, command vs movement identity, chybějící payer reference/signed direction, kurzor recovery a společný polling lock. V2 pro Festapp přidej explicitní consumer capability; zachovej stávající Mendelio v1 public contract a archivní payloady. Nesmíš přepnout shared writer způsobem vyžadujícím neautorizovaný rollout všech Mendelio aplikací.

Receiver ověří raw-body HMAC přes pinovaný kanonický balíček, account mapping a atomický SQL inbox/identity/ledger/matcher/receipt commit. Žádný druhý mark-paid engine nebo falešné HTTP 200. Zachovej odchozí/manual/CASH evidenci a nezávislé zasílání vstupenek. Nezaváděj compatibility triggers, dva /last čtenáře tokenu, trvalý legacy fallback ani placeholdery.

Evidence snapshot je v `docs/plans/evidence/banksync-2026-10-03/observations.json`. Při změně facts oprav samotný plán a dotčené vlny. Novější terminal jobs a fyzická duplicita účtu vyžadují disposition, ne slepý replay nebo SQL merge.

Pro implementaci vyžaduj samostatné zadání. Tento plán sám neautorizuje commit/push, produkční migrace/deploy, provisioning/rotation, bankovní fetch/pointer, SNS/MX změny nebo replay. Před budoucí produkční fází připrav konkrétní reviewable scoped manifest, digests a validation. Před první publikací fetch authoritative upstream a aktualizuj stale base podle repo pravidel.

Na handoff stručně uveď dosažený M1/M2, změněnou smlouvu, výsledky cílených kontrol, odstraněné legacy cesty a přesný zbývající provozní krok. Nedeklaruj kompletní cutover, pokud zbývá neověřená aktivní ingress cesta.
