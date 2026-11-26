# #1069 Nákup z kampaně v prohlížeči uvnitř aplikace

## Příčina a rozhodnutí

Samostatný odkaz od `installHostConsentLink` potřebuje živý `WindowProxy`.
Při `pagehide` host ukončí relaci. `requestLinkedConsent` vyžaduje ověřený
opener, jeho origin, scope a revizi. Messenger na Androidu podle issue
naviguje ve stejném kontextu nebo neposkytne opener. V obou případech je
místní cookie lišta správný bezpečný fallback. Prohlížeč nelze spolehlivě
rozpoznat před kliknutím a po navigaci už může být hostitelská stránka pryč.

Provozovatel kampaně může zvolit cíl přímo na stránce pořadatele. Přidá ID
stávajícímu iframe a hodnotu `data-festapp-consent-link-embed` na označený
odkaz. Výsledek je stejný v každém prohlížeči pro tento konkrétní odkaz.
Stránka, která má jen samostatný odkaz, musí nejprve dostat generovaný embed.
Samostatný záložní odkaz v generovaném bloku zůstává dostupný při omezení
iframe. Úprava je výslovná volba pořadatele. Nevytváří automatický overlay,
detekci user-agentů nebo token souhlasu.

## Implementace

1. Prověř předchozí lokální diff z větve `fix/consent-link-in-app` ve worktree
   `~/Developer/festapp-consent-link-1069`. Na stejném základu prošel
   371 testy, prohlížečovým `test:measurement-cmp` a kontrolou bundle.
   Přenes jen relevantní zdroj, test a dokumentaci se znalostí aktuálního
   main. Tento plán nahrazuje původní plán issue v rámci společného PR.
2. V `web_client/src/embed/host_consent_link.js` dej běžnému kliknutí na
   výslovně označený odkaz navigační volbu k existujícímu renderovanému
   `iframe[data-festapp-embed]`. Podmínkou je shodný tenant a URL formuláře
   včetně parametrů a fragmentu, s přesně jedním `embed=1` na iframe.
   Odmítni neplatný, skrytý, inertní, sandboxovaný nebo `srcdoc` cíl. Nic
   v iframe nepřenačítej. Přesuň fokus a jednou odhal cíl, bez vynuceného
   pohybu pro omezené animace. Modifikátory, download a stávající
   referrer/target pravidla ponech nativnímu chování. Neúspěšný výběr
   přejde na dosavadní samostatnou cestu.
3. Souhlas i jeho odvolání dál vlastní `EmbedChannel`,
   `createHostMeasurement` a příslušný adaptér CMP. Režim dataLayer webu
   ponechá kontrolu GTM webu. Režim jednotky připouští pouze oprávněný živý
   zdroj. Meta CAPI zůstává na stávajícím záznamu platného souhlasu a stavu
   objednávky. Zachovej standardní fallback při chybějící nebo neaktuální
   volbě. Nepřidávej storage, nové zprávy, URL s rozhodnutím nebo backend.
4. Přegeneruj `public/embed.js`. Do `docs/integrations/embedded-checkout.md`
   dej příklad konfigurace se samostatným záložním odkazem a omezení pro
   stránku bez iframe. Stručný pokyn doplň na existující místo nápovědy měření
   v CS/SK/EN. Sjednoť tvrzení o ručních odkazech s výslovným opt-in.
   Neměň generátory ani chování výchozích odkazů. Stávající exporty CMS
   zůstávají zdrojem konfigurace, případný UX v editoru pluginů je zvlášť.

## Akceptace a kontrola

- Skutečný bundle, host a iframe na dvou origínech v
  `pnpm --dir web_client run test:measurement-cmp`. Ověř Enter i běžné
  kliknutí, fokus, skrol, žádný popup, stejný dokument v iframe a změnu či
  odvolání zdroje po přesunu. Při testu potvrď identitu dokumentu,
  instance kanálu může přežít reload. Stav relace čekej deterministicky.
  Ověř odklon na fallback při chybějícím/skrytém cíli, rozdílné URL
  či bez opt-in a nativní chování při modifikátorech.
- Cíleně spusť `tests/forms/form_consent_link*.test.js`,
  `form_measurement_embed_consent.test.js`, testy hostitelských adaptérů,
  `node scripts/build_embed.mjs --check` a dotčené CI lane. Pokryj
  #824 (Cookiebot), #782 (standalone s platným openerem), #1008
  (návrat k formuláři), #781 (obě nastavení měření).
- S dostupnou testovací stránkou a oprávněným Messengerem na Androidu
  projdi přijmout, odmítnout i částečný souhlas z Cookiebotu. Zkontroluj
  pokračování bez druhé lišty a zachování explicitního fallbacku. Použij
  testovací tenant bez produkčních nákupů nebo odesílání konverzí.
  Bez tohoto zařízení a stránky je prohlížečový test důkazem chování
  embedu. Ověření konkrétního Messengeru vykazuj samostatně. Dokud chybí,
  v PR použij `Refs #1069`, případné uzavření ponech po ověření.
