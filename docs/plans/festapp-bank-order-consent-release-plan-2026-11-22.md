# Atomické pořadí účtů a stabilní souhlas pro Meta CAPI

Základ `d61412673`, ověření standard. Produkční web je `vstupenky.online`, větev `prod/festapptickets`.

1. Přidat akci `reorder` do `manage_bank_authoring` a stávajícího protokolu příkazů s potvrzením. Pod zámkem jednotky porovnat původní pořadí se stavem serveru. Po kladném ověření oprávnění a úplné permutace aktualizovat priority jedním příkazem. Odmítnout neaktuální seznam a cizí účty, vytvořit jedno potvrzení a zachovat stávající akci pro připojení a odpojení. Flutter nahradí cyklus jedním příkazem a při konfliktu obnoví seznam.
2. Relace měření bude porovnávat identitu přenosu souhlasu podle `consentTransportManifest` samostatně od manifestu GTM. Stabilní identita zachová existující vazbu. Změna jejího rozsahu dál obnoví kontrolu, GTM vyžaduje vlastní platný manifest a výpadek kontroly nadále znemožní použití souhlasu při objednávce.
3. Ověřit atomické pořadí, zastaralý seznam, replay a oprávnění v SQL; ověřit Flutter účetní rozhraní a přechod mezi objednávkou a formulářem bez GTM. Vygenerovat dopřednou migraci a paritu a ověřit inventář testů.
4. Ověřit CI finálního `main` přes `release_gate.py`. Použít jedinou aktuální verzi sdílenou na `main` a připravit kompatibilní migrace před webovým klientem. Nasadit jedinou produkční větev přes schválený lokální build a `deploy_direct.sh`, ověřit veřejnou verzi, artefakt a účetní oprávnění.
