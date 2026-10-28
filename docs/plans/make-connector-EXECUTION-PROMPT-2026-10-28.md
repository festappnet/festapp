# Proveď sjednocení Make konektoru a dokončení existujícího review

Pracuj v `/Users/miakh/source/festapp`. Přečti AGENTS.md, CLAUDE.md, docs/architecture/ai_context.md a celý jediný autoritativní [plán](make-connector-plan-2026-10-28.md). Verification: standard.

Review připomínky již byly zpracované, stejná app/verze aktualizovaná a odpověď `1a18258af1b4ad0b` odeslaná v případu `2351677:2082001`. Neopakuj účet, provisioner, Publish, Request review, navazující formulář ani odpověď. Schválení/vydání není doložené. Stav a historické důkazy jsou v `integrations/make/evidence/execution-20261028.json`; nepleť je s dnešním runtime nebo dirty worktree.

Proveď čtyři vlny plánu: jediné schéma reportu nad skutečným SQL; společný Make kontrakt a přesný generátor; jediná SDK hranice a neměnné důkazy; odstranění starých cest a sjednocení dokumentace. Zachovej Operations.invoke, scope owner, DelegatedOwner a order-summary projekci. Samples nesmí vlastnit typy. Zachovej machine keys/identity, text report ID a money reprezentace, klientskou izolaci, fixed-origin read allowlist, sedmidenní consent, blank/default limit a úplné pagination body. Nepřidávej další REST backend, schema kopii, alias ani framework.

Checkout obsahuje cizí změny; izoluj vlastní práci a nic cizího nemaž/nepublikuj. Pokud zdroj vyvrátí předpoklad, oprav plán konkrétním důkazem a přizpůsob vlnu. Splň deletion ledger včetně obsolete generated souborů. Historické freeze/qualification/readback nepřepisuj.

Po souvislé změně spusť cílené checks plánu přes pnpm 11.24.0 a marker-ověřenou disposable SQL DB. Skip není PASS. Neopakuj nezměněné kontroly, netestuj exact prose a nespouštěj Flutter.

Toto zadání nerozšiřuje produkční/publikační autoritu. Deploy/push/zápis do Make jen v doloženém existujícím rozsahu, s přesným čistým source revision/digestem a příslušnými gates. Pokud se generated definice nezmění, žádný sync/živé scénáře. Pokud ano a review state dovoluje update, použij stejnou app `vstupenky-online-buoz5u` v1/EU1, readback a jednou relevantní existující on-demand scénáře; na konci inactive. Rutinní autorizovaný deploy deleguj dle AGENTS.md levnějšímu agentovi. Žádná nová zpráva bez konkrétního oprávnění, placený závazek nebo vedlejší tenant rollout.

Na konci stručně uveď kanonické vlastníky, odstraněné duplicity, testy, případný digest a neprovedené provozní kroky. Lokální dokončení odděl od čekání na Make. Katalogové vydání potvrď až po skutečném approval/discovery/OAuth důkazu. Při čekání zapiš závislost a skonči bez polling smyčky.
