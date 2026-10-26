# Aktualizace platformy

Jediným zdrojem je `<id>/meta.json`, `cs.md` a `en.md`. ID tvoří malá ASCII
písmena, číslice a jednotlivé pomlčky; složka se musí jmenovat stejně. ID po
publikaci neměňte. Neověřená dostupnost funkce patří do draftu.

Metadata:

```json
{
  "id": "stabilni-identita",
  "status": "draft",
  "kind": "improvement",
  "publishedAt": "2026-10-26T08:00:00Z",
  "translations": {
    "cs": {"title": "Český titulek", "summary": "Přínos pro pořadatele."},
    "en": {"title": "English title", "summary": "Benefit for organizers."}
  }
}
```

Toto je ukázka formátu, nikoli veřejný příspěvek. `kind` je `feature`,
`improvement` nebo `fix`. Draft může mít neúplné překlady. Publikace vyžaduje
oba titulky, shrnutí, těla a platný UTC čas, který neleží v budoucnosti.
Volitelný `updatedAt` nesmí předcházet publikaci ani ležet v budoucnosti.

Markdown podporuje odstavce, nadpisy, seznamy a odkazy HTTPS/mailto. HTML,
embedy a nebezpečné URL jsou zakázané. Obrázky s neprázdným alt textem musí být
uložené ve `web/platform-updates-media/` (PNG/JPEG/WebP/GIF) a používat absolutní
cestu `/platform-updates-media/soubor.webp`. Chybějící asset zastaví sestavení.
Nadpisy v těle začínají pod hlavním titulkem dokumentu.

Lokální preview bez serveru:

```sh
pnpm --dir automation/release/platform_updates install --frozen-lockfile
node automation/release/platform_updates/preview.mjs --output /tmp/festapp-platform-updates-preview
```

Otevřete vygenerovaný `cs-index.html` přímo z disku. Preview zahrnuje pouze
publikované položky. Draft lze zkontrolovat v dočasné kopii obsahového adresáře
s `status: published` a `--content <adresář>`; takovou kopii nikdy nepublikujte.

Před prvním zveřejněním ověřte dostupnost konkrétní funkce na cílovém tenantu
a skutečné datum. Potom změňte status na `published`, spusťte cílené testy z
plánu a samostatně autorizovaný web release. HTML, feed, sitemap, Worker a PWA
se publikují v jednom bundle. Tenant má aktualizace jen při explicitním
`platformUpdates: true` ve svém marketingovém profilu. `apply_config.sh`
odvozuje ze stejného kontextu viditelnost odkazu v administraci.

Oprava textu zachovává ID i `publishedAt`; podle potřeby přidejte `updatedAt`.
Žádný krok automaticky neposílá zprávy. Veřejný `/platform-updates.json`
obsahuje pouze explicitní projekci metadat a překladů. Budoucí upozornění
odkazují na `platform_update_id`; deduplikace podle ID, příjemce a kanálu musí
být nezávislá na jazyce. Pro nepodporovaný jazyk použijí angličtinu. Osobní
upozornění ani eventové news nejsou tímto archivem změněny.

Veřejná hlavička a patička používají kanonické komponenty v
`automation/release/organizers/site_shell.mjs`. Nevytvářejte pro aktualizace
další hlavičku ani lokální jazykový přepínač. Odkaz „Co je nového“ patří
do patičky a společné administrace.
