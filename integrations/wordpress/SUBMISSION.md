# vstupenky.online - podklady pro WordPress.org

**Review 2026-10-27:** WordPress.org vyžádal shodné `Requires at least: 6.6`
v hlavičce pluginu a readme místo `6.6.4`. Český kandidát **1.0.3** opravu
obsahuje; čistá instalace a aktivace, 39 reálných kontraktů a Plugin Check 2.1.0
prošly na WordPressu 6.6 / PHP 7.4.33. Plugin Check: 0 errors, 1 dříve
zdokumentované upozornění na překlady pro samostatnou ZIP instalaci.
Opravený ZIP byl nahrán do stejné žádosti a odpověď odeslána v původním review
vlákně. Schválení katalogu nadále čeká. Záznam: `evidence/review-response-20261027.json`;
historické potvrzení verze 1.0.0 zůstává beze změny. Nezakládat další žádost.

**Podáno 2026-10-24:** vstupenky.online 1.0.0, předběžný slug
`vstupenky-online`. Automatická kontrola WordPress.org: **Pass**.
Ruční kontrola: **Awaiting Review**. Plugin ještě není veřejně v katalogu.
Receipt: `evidence/submission-20261024.json`. Další distribuci nepodávat.


Aktuální rozsah je pouze **vstupenky.online 1.0.0**, účet vydavatele
**festappnet**, kontakt **info@festapp.net**. Festapp Tickets se nyní nepodává
ani se neaktualizuje jeho ZIP nebo SVN návrh.

## Současný stav: produkční služba ověřena

Vstupenky.online 0.20.389+889 byla vydána z mainu `db6db44d5` přes tenant
`fa0de1bd2`. Skutečný cross-origin WordPress embed z finálního ZIPu prošel
načtením, automatickou výškou, otevřením plánku, Escape a obnovou scrollu.
Podrobnosti: `evidence/production-release-20261024.json`.
SaaS integrace je přípustná podle [pravidel 6-8](https://developer.wordpress.org/plugins/wordpress-org/detailed-plugin-guidelines/);
přijetí konkrétního podání posuzuje WordPress.org ručně.

## Konkrétní balíček a povinná kontrola před podáním

- ZIP: `dist/vstupenky-online-1.0.0.zip`.
- Offline SVN: `dist/wordpress-org-draft/`.
- Přesné hashe a otevřené brány: `dist/APPROVAL.json`.
- Kritik a výsledky: `evidence/publishability-review-20261024.json`.

Z tohoto adresáře:

```sh
pnpm run package --product vstupenky-online
python3 scripts/stage-submission.py --product vstupenky-online
python3 scripts/verify-submission.py --product vstupenky-online
python3 scripts/verify-submission.py --product vstupenky-online --submit-ready
```

První dva příkazy mění vstupy zapečetěného návrhu. Po změně aktualizujte skutečné
výsledky a seal, nikoli jen hashe. Poslední příkaz musí před odesláním projít;
dokud jsou produkční brány otevřené, záměrně selže.

## Po splnění produkčních bran

Ověřit aktuální stav žádostí na [stránce pro přidání pluginu](https://wordpress.org/plugins/developers/add/),
přihlášení správným účtem a pravidla podání. Odeslat jen vybraný zapečetěný ZIP
v rámci vlastníkem autorizovaného podání. WordPress.org obvykle dovoluje jednu
čekající žádost; [FAQ](https://developer.wordpress.org/plugins/wordpress-org/plugin-developer-faq/)
odmítá obcházení více účty a pouhé duplicitní pluginy. Globální varianta není
součástí tohoto návrhu.

Podání k review není veřejné vydání. Po přijetí ověřit skutečně přidělený slug
a SVN repozitář, připravit diff a v autorizovaném veřejném vydání publikovat
ověřené trunk/tag/assets. Nakonec ověřit instalaci z katalogu a veřejnou stránku.
Schválení, rezervaci slugu ani datum vydání nelze předem slíbit.
