# Implementace kontroly koncovky e-mailové domény

Archiv: implementováno a lokálně ověřeno 2026-10-24. Nejde o nové pověření k realizaci.

Pracuj v `/Users/miakh/source/festapp`. Přečti aktuální `AGENTS.md`, `CLAUDE.md`,
`docs/architecture/ai_context.md` a celý autoritativní plán:

`docs/archive/plans/email-domain-suffix-validation-plan-2026-10-24.md`

Implementuj všechny tři kroky plánu. Cílem je lokální kontrola koncovky podle
úplného IANA snapshotu v JS a Flutter veřejných formulářích a webové registraci.
Neznámá koncovka vyžaduje výslovné potvrzení konkrétní hodnoty konkrétního pole,
ne automatickou opravu nebo trvalý zákaz odeslání. Login, reset a Google proof
nepřipojuj k novému potvrzování. Kontrola neprokazuje existenci schránky.

Použij verification: standard s cílenými kontrolami plánu, pnpm 11.24.0 a FVM.
Spouštěj nejvýše jednu Flutter úlohu na workstation a testy s `--concurrency=1`.
Zachovej rozpracované změny ostatních. Nedělej nový architektonický průzkum ani
nezávislý audit; dohledání přesného Flutter submit místa je omezený úkol uvedený
v plánu. Pokud důkazy vyvrátí předpoklad plánu, nejprve ho konkrétně oprav.

Nenechávej placeholdery, ruční kopie seznamu ani paralelní odesílací cesty.
Hotovo vyžaduje datovou shodu obou klientů, testy potvrzení a jeho zrušení po
editaci, nepřítomnost dvojího submitu a zachování existujících auth cest.
Bez samostatného zadání necommituj, nepushuj, nenasazuj a neměň backend ani data.
Při předání stručně popiš výsledek, validaci a případný konkrétní zbylý blokátor.
